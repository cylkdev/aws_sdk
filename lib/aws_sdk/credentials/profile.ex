defmodule AwsSDK.Credentials.Profile do
  @moduledoc """
  Loads a named profile by merging entries from `~/.aws/config` and
  `~/.aws/credentials`, and dispatches the loaded profile to the
  correct credential-resolution strategy.

  In `~/.aws/config`, profiles (other than `default`) are stored under
  `[profile foo]`. In `~/.aws/credentials`, the same profile lives
  under `[foo]`. Keys present in both files are resolved with
  `~/.aws/credentials` winning, matching the AWS CLI's behavior.

  The `sso-session` blocks in `~/.aws/config` are exposed via
  `load_sso_session/2`.

  `security_credentials/2` is the entry point consumed by
  `AwsSDK.AuthCache` for the `{:awscli, profile, ttl}` source. It
  inspects the loaded profile and dispatches to the matching provider
  (SSO, credential_process, AssumeRole, or static keys).
  """

  alias AwsSDK.Credentials.INI

  alias AwsSDK.Credentials.Providers.{
    AssumeRole,
    CredentialProcess,
    LoginSession,
    SSO,
    StaticProfile
  }

  @type profile :: %{optional(String.t()) => String.t()}

  @doc """
  Returns the effective `~/.aws/config` path, honoring the
  `AWS_CONFIG_FILE` env var and the `:home_dir` opt.

  ## Examples

      AwsSDK.Credentials.Profile.config_path()
      #=> "/Users/you/.aws/config"

      # AWS_CONFIG_FILE wins when set.
      System.put_env("AWS_CONFIG_FILE", "/etc/aws/config")
      AwsSDK.Credentials.Profile.config_path()
      #=> "/etc/aws/config"
  """
  @spec config_path(keyword) :: Path.t()
  def config_path(opts \\ []) do
    System.get_env("AWS_CONFIG_FILE") || default_config_path(opts)
  end

  defp default_config_path(opts), do: opts |> home() |> Path.join(".aws/config")

  @doc """
  Returns the effective `~/.aws/credentials` path, honoring the
  `AWS_SHARED_CREDENTIALS_FILE` env var and the `:home_dir` opt.

  ## Examples

      AwsSDK.Credentials.Profile.credentials_path()
      #=> "/Users/you/.aws/credentials"

      # AWS_SHARED_CREDENTIALS_FILE wins when set.
      System.put_env("AWS_SHARED_CREDENTIALS_FILE", "/etc/aws/creds")
      AwsSDK.Credentials.Profile.credentials_path()
      #=> "/etc/aws/creds"
  """
  @spec credentials_path(keyword) :: Path.t()
  def credentials_path(opts \\ []) do
    System.get_env("AWS_SHARED_CREDENTIALS_FILE") || default_credentials_path(opts)
  end

  defp default_credentials_path(opts), do: opts |> home() |> Path.join(".aws/credentials")

  @doc """
  Loads a named profile, returning the merged key/value map or `nil`
  when the profile is defined in neither file.

  ## Examples

      AwsSDK.Credentials.Profile.load("dev")
      #=> %{
      #=>   "region" => "eu-west-1",
      #=>   "role_arn" => "arn:aws:iam::123456789012:role/dev",
      #=>   "source_profile" => "default"
      #=> }

      AwsSDK.Credentials.Profile.load("no-such-profile")
      #=> %{}

  Merges the two shared files, with `~/.aws/credentials` taking precedence.
  In `~/.aws/config` the section is `[profile dev]`; in `~/.aws/credentials`
  it is `[dev]`. Both resolve from the same `"dev"` name.
  """
  @spec load(String.t(), keyword) :: profile | nil
  def load(profile_name, opts \\ []) when is_binary(profile_name) do
    config = load_file(config_path(opts))
    creds = load_file(credentials_path(opts))

    config_entry = Map.get(config, config_section_name(profile_name), %{})
    creds_entry = Map.get(creds, profile_name, %{})

    case Map.merge(config_entry, creds_entry) do
      empty when map_size(empty) === 0 -> nil
      merged -> merged
    end
  end

  @doc """
  Loads an `[sso-session NAME]` block from `~/.aws/config`.

  Returns the session's key/value map or `nil` when no such block
  exists.

  ## Examples

      AwsSDK.Credentials.Profile.load_sso_session("my-sso")
      #=> %{
      #=>   "sso_start_url" => "https://example.awsapps.com/start",
      #=>   "sso_region" => "us-east-1",
      #=>   "sso_registration_scopes" => "sso:account:access"
      #=> }

  Reads an `[sso-session my-sso]` section, which is the modern form a
  profile references via `sso_session = my-sso`.
  """
  @spec load_sso_session(String.t(), keyword) :: profile | nil
  def load_sso_session(session_name, opts \\ []) when is_binary(session_name) do
    config = load_file(config_path(opts))
    Map.get(config, "sso-session " <> session_name)
  end

  @doc """
  The default profile name, honoring `AWS_PROFILE` then `AWS_DEFAULT_PROFILE`.

  ## Examples

      AwsSDK.Credentials.Profile.default()
      #=> "default"

      # AWS_PROFILE overrides it.
      System.put_env("AWS_PROFILE", "dev")
      AwsSDK.Credentials.Profile.default()
      #=> "dev"
  """
  @spec default :: String.t()
  def default do
    System.get_env("AWS_PROFILE") || System.get_env("AWS_DEFAULT_PROFILE") || "default"
  end

  @doc """
  Resolves credentials for a named profile by dispatching based on
  profile content.

  Dispatch order:

    1. `sso_session` or `sso_start_url` → `AwsSDK.Credentials.Providers.SSO`
    2. `credential_process` → `AwsSDK.Credentials.Providers.CredentialProcess`
    3. `login_session` → `AwsSDK.Credentials.Providers.LoginSession`
    4. `role_arn` → `AwsSDK.Credentials.Providers.AssumeRole`
    5. `aws_access_key_id` → `AwsSDK.Credentials.Providers.StaticProfile`

  `credential_process` wins over `login_session` when both are present
  so an explicit override is always respected.

  Returns `{:ok, creds}` where `creds` is a map with at least
  `:access_key_id` and `:secret_access_key`, plus `:security_token`,
  `:expires_at`, `:region`, and `:source` when available.

  Returns `{:error, reason}` when the profile cannot be resolved or
  does not carry any of the dispatch keys above.

  ## Examples

      AwsSDK.Credentials.Profile.security_credentials("dev")
      #=> {:ok,
      #=>  %{
      #=>    access_key_id: "ASIA1EXAMPLE",
      #=>    secret_access_key: "...",
      #=>    security_token: "IQoJb3JpZ2luX2VjEJr...",
      #=>    expires_at: ~U[2026-01-01 01:00:00Z],
      #=>    source: :sts
      #=>  }}

      AwsSDK.Credentials.Profile.security_credentials("no-such-profile")
      #=> {:error, :no_credentials}

  Picks the provider the profile implies: static keys, `role_arn` +
  `source_profile` (AssumeRole), `sso_session` (SSO), or
  `credential_process`. `:source` says which one answered.
  """
  @spec security_credentials(String.t(), keyword) :: {:ok, map} | {:error, term}
  def security_credentials(profile_name, opts \\ []) when is_binary(profile_name) do
    case load(profile_name, opts) do
      nil ->
        {:error, {:profile_not_found, profile_name}}

      profile ->
        provider_opts = Keyword.put(opts, :profile, profile_name)

        profile
        |> dispatch(provider_opts)
        |> interpret_dispatch(profile_name)
        |> maybe_put_region(profile)
    end
  end

  defp dispatch(profile, opts) do
    cond do
      is_binary(profile["sso_session"]) or is_binary(profile["sso_start_url"]) ->
        SSO.resolve(opts)

      is_binary(profile["credential_process"]) ->
        CredentialProcess.resolve(opts)

      is_binary(profile["login_session"]) ->
        LoginSession.resolve(opts)

      is_binary(profile["role_arn"]) ->
        AssumeRole.resolve(opts)

      is_binary(profile["aws_access_key_id"]) ->
        StaticProfile.resolve(opts)

      true ->
        {:error, :unresolvable_profile}
    end
  end

  defp interpret_dispatch({:ok, creds}, _profile_name), do: {:ok, creds}
  defp interpret_dispatch({:error, _} = err, _profile_name), do: err

  defp interpret_dispatch(:skip, profile_name),
    do: {:error, {:unresolvable_profile, profile_name}}

  defp maybe_put_region({:ok, creds}, profile) do
    case profile["region"] do
      region when is_binary(region) and region !== "" ->
        {:ok, Map.put_new(creds, :region, region)}

      _ ->
        {:ok, creds}
    end
  end

  defp maybe_put_region(result, _profile), do: result

  defp config_section_name("default"), do: "default"
  defp config_section_name(profile), do: "profile " <> profile

  defp load_file(path) do
    case INI.read(path) do
      {:ok, sections} -> sections
      {:error, _} -> %{}
    end
  end

  defp home(opts) do
    opts[:home_dir] || System.user_home!()
  end
end
