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

  alias AwsSDK.Credentials.Secrets
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
  Loads a named profile from both shared files, unmerged.

  Returns `read/2`'s per-file map, or `nil` when the profile has a section
  in neither file. Look keys up with `value/2`, which applies the AWS CLI's
  precedence (`~/.aws/credentials` over `~/.aws/config`).

  ## Examples

      AwsSDK.Credentials.Profile.load("dev")
      #=> %{
      #=>   config: %{
      #=>     path: "/Users/you/.aws/config",
      #=>     read: {:ok, %{"profile dev" => %{"region" => "eu-west-1", ...}}},
      #=>     section: %{"region" => "eu-west-1", "role_arn" => "arn:aws:iam::123456789012:role/dev"}
      #=>   },
      #=>   credentials: %{path: "/Users/you/.aws/credentials", read: {:error, :enoent}, section: nil}
      #=> }

      AwsSDK.Credentials.Profile.load("no-such-profile")
      #=> nil
  """
  @spec load(String.t(), keyword) :: map | nil
  def load(profile_name, opts \\ []) when is_binary(profile_name) do
    case read(profile_name, opts) do
      %{config: %{section: nil}, credentials: %{section: nil}} -> nil
      files -> files
    end
  end

  @doc """
  Looks `key` up in a profile loaded by `load/2`: the `~/.aws/credentials`
  section first, then the `~/.aws/config` section (the AWS CLI's precedence
  rule). Returns `nil` when neither section has it.

  ## Examples

      profile = AwsSDK.Credentials.Profile.load("dev")
      AwsSDK.Credentials.Profile.value(profile, "region")
      #=> "eu-west-1"
  """
  @spec value(map, String.t()) :: String.t() | nil
  def value(%{config: config, credentials: credentials}, key) when is_binary(key) do
    case credentials.section do
      %{^key => found} -> found
      _ -> config.section && Map.get(config.section, key)
    end
  end

  @doc """
  Reads a named profile from each shared file separately, without merging.

  Returns one map per file: its `:path`, the raw `:read` result
  (`{:ok, sections}` or `{:error, reason}`, so an unreadable or missing file
  is reported rather than treated as empty), and the profile's `:section`
  in that file (`nil` when absent). `load/2` is the merged view the
  providers resolve against; this is the facts it was built from.

  ## Examples

      AwsSDK.Credentials.Profile.read("dev")
      #=> %{
      #=>   config: %{
      #=>     path: "/Users/you/.aws/config",
      #=>     read: {:ok, %{"profile dev" => %{"region" => "eu-west-1"}}},
      #=>     section: %{"region" => "eu-west-1"}
      #=>   },
      #=>   credentials: %{
      #=>     path: "/Users/you/.aws/credentials",
      #=>     read: {:error, :enoent},
      #=>     section: nil
      #=>   }
      #=> }
  """
  @spec read(String.t(), keyword) :: %{config: map, credentials: map}
  def read(profile_name, opts \\ []) when is_binary(profile_name) do
    %{
      config: read_section(config_path(opts), config_section_name(profile_name)),
      credentials: read_section(credentials_path(opts), profile_name)
    }
  end

  defp read_section(path, section_name) do
    read = INI.read(path)

    section =
      case read do
        {:ok, sections} -> Map.get(sections, section_name)
        {:error, _} -> nil
      end

    %{path: path, read: read, section: section}
  end

  @doc """
  Loads an `[sso-session NAME]` block from `~/.aws/config`.

  Returns the session's key/value map or `nil` when no such block
  exists.

  ## Examples

      AwsSDK.Credentials.Profile.load_sso_session("my-sso")
      #=> %{
      #=>   path: "/Users/you/.aws/config",
      #=>   read: {:ok, %{...}},
      #=>   section: %{
      #=>     "sso_start_url" => "https://example.awsapps.com/start",
      #=>     "sso_region" => "us-east-1",
      #=>     "sso_registration_scopes" => "sso:account:access"
      #=>   }
      #=> }

  Returns the file's `:path`, raw `:read` result and the `:section`
  (`nil` when absent). Reads an `[sso-session my-sso]` section, which is the modern form a
  profile references via `sso_session = my-sso`.
  """
  @spec load_sso_session(String.t(), keyword) :: map
  def load_sso_session(session_name, opts \\ []) when is_binary(session_name) do
    read_section(config_path(opts), "sso-session " <> session_name)
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
  `:expires_at`, `:region`, and `:source` when available, and
  `:profile_files` — the unmerged per-file facts from `read/2`.

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
        |> put_profile_files(profile)
    end
  end

  defp dispatch(profile, opts) do
    cond do
      is_binary(value(profile, "sso_session")) or is_binary(value(profile, "sso_start_url")) ->
        SSO.resolve(opts)

      is_binary(value(profile, "credential_process")) ->
        CredentialProcess.resolve(opts)

      is_binary(value(profile, "login_session")) ->
        LoginSession.resolve(opts)

      is_binary(value(profile, "role_arn")) ->
        AssumeRole.resolve(opts)

      is_binary(value(profile, "aws_access_key_id")) ->
        StaticProfile.resolve(opts)

      true ->
        {:error, :unresolvable_profile}
    end
  end

  defp interpret_dispatch({:ok, creds}, _profile_name), do: {:ok, creds}
  defp interpret_dispatch({:error, _} = err, _profile_name), do: err

  defp interpret_dispatch(:skip, profile_name),
    do: {:error, {:unresolvable_profile, profile_name}}

  # The per-file facts this profile resolved from, kept unmerged.
  defp put_profile_files({:ok, creds}, profile) do
    {:ok, Map.put(creds, :profile_files, Secrets.strip(profile))}
  end

  defp put_profile_files(result, _profile), do: result

  defp config_section_name("default"), do: "default"
  defp config_section_name(profile), do: "profile " <> profile

  defp home(opts) do
    opts[:home_dir] || System.user_home!()
  end
end
