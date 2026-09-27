defmodule AwsSDK.Config do
  @moduledoc """
  Runtime configuration for the `:aws_sdk` library.

  ## Credentials resolve as one unit

  An access key, its secret, and its session token are a single
  indivisible credential set: they are minted together and only valid
  together. `credentials/1` therefore walks **one** source chain and
  returns the first source that yields a complete set. It never
  assembles a set from more than one source, and — because
  `AwsSDK.AuthCache` is single-flight — never from more than one mint.

  The chain is held in a module attribute and can be replaced wholesale
  via `Application.put_env(:aws_sdk, :credentials, chain)` or per call with
  `:profile`.

  ### Credential source chain entries

    | Entry                          | Resolves to                                                     |
    |--------------------------------|-----------------------------------------------------------------|
    | `:env`                         | `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` (+ `AWS_SESSION_TOKEN`), only when both key and secret are set |
    | `:app_env`                     | the `:aws_sdk` `:access_key_id` + `:secret_access_key` (+ `:security_token`) app-env pair |
    | `:instance_role`               | EC2 IMDSv2 credentials                                          |
    | `:ecs_task_role`               | ECS container credentials                                       |
    | `{:awscli, profile}`           | shared-config profile (static / SSO / credential_process / assume_role) |
    | `{:awscli, {:system, "VAR"}}`  | profile name read from an env var, then dispatched as `{:awscli, profile}` |
    | a map                          | itself, when it carries `:access_key_id` and `:secret_access_key` |

  ### Region source chain entries

  Region is not a secret and has independent sources, so it keeps its
  own chain: a binary literal resolves to itself, `{:system, "VAR"}` to
  that env var. The region carried by the resolved credential set is
  consulted between the app-env chain and `AWS_REGION`.

  ## Precedence

  **Per-call opts > `:profile` > app env > built-in defaults.**

  Per-call `:access_key_id` and `:secret_access_key` must be given
  *together* — they form a complete source that short-circuits the
  chain. Supplying only one raises, because pairing an explicit key
  with a secret drawn from somewhere else produces a signature AWS
  rejects.

  ## Naming a profile per call

  Passing `:profile` resolves the credential set and the region from
  that named shared-config profile:

      AwsSDK.EC2.describe_instances(profile: "cylk-admin", region: "us-east-1")

  This reads only `~/.aws/*` — the built-in chain, which would otherwise
  consult `AWS_PROFILE` and `AWS_ACCESS_KEY_ID`, is skipped entirely, so
  neither the system nor the application environment can change which
  credentials are used. SSO, `credential_process`, `assume_role`, and
  static profiles all resolve through this path. `:profile_ttl_seconds`
  overrides the 30-second credential cache lifetime.

  ## Sandbox configuration

  `sandbox/1` returns a merged keyword list combining the built-in
  defaults, the `:aws_sdk` `:sandbox` app-env entry, and the `:sandbox`
  key in caller opts.
  """

  alias AwsSDK.AuthCache

  @app :aws_sdk

  @credentials [
    {:awscli, {:system, "AWS_PROFILE"}},
    {:awscli, "default"},
    :env,
    :app_env,
    :instance_role,
    :ecs_task_role
  ]

  @region [
    {:system, "AWS_REGION"},
    {:system, "AWS_DEFAULT_REGION"},
    "us-east-1"
  ]

  @sandbox [enabled: false]

  @default_profile_ttl_seconds 30

  @doc """
  Aggregates the resolved credential set, region and sandbox flag into
  a single keyword list.

  ## Examples

      AwsSDK.Config.new(access_key_id: "AKIA1EXAMPLE", secret_access_key: "SK", region: "eu-west-1")
      #=> [
      #=>   access_key_id: "AKIA1EXAMPLE",
      #=>   secret_access_key: "SK",
      #=>   security_token: nil,
      #=>   region: "eu-west-1",
      #=>   sandbox: [enabled: false]
      #=> ]

      # With nothing passed, every key is resolved from the app env and the
      # built-in source chain.
      AwsSDK.Config.new()
      #=> [access_key_id: "...", secret_access_key: "...", region: "us-east-1", ...]
  """
  @spec new(keyword) :: keyword
  def new(opts \\ []) when is_list(opts) do
    creds = credentials(opts)

    [
      access_key_id: creds[:access_key_id],
      secret_access_key: creds[:secret_access_key],
      security_token: creds[:security_token],
      region: region(opts, creds),
      sandbox: sandbox(opts)
    ]
  end

  @doc """
  Resolves the credential chain, returning the first complete set as a
  map with `:access_key_id`, `:secret_access_key` and — when the source
  provides them — `:security_token` and `:region`.

  Returns an empty map when no source yields credentials.

  ## Examples

      AwsSDK.Config.credentials(access_key_id: "AKIA1EXAMPLE", secret_access_key: "SK")
      #=> %{
      #=>   access_key_id: "AKIA1EXAMPLE",
      #=>   secret_access_key: "SK",
      #=>   security_token: nil
      #=> }

      # Resolve everything from a named shared-config profile.
      AwsSDK.Config.credentials(profile: "dev")
      #=> %{
      #=>   access_key_id: "ASIA1EXAMPLE",
      #=>   secret_access_key: "...",
      #=>   security_token: "IQoJb3JpZ2luX2VjEJr..."
      #=> }

  Passing `:profile` skips the built-in chains entirely, so nothing is read
  from the system or application environment. Precedence is
  explicit key opt > `:profile` > app env > built-in defaults.
  """
  @spec credentials(keyword) :: map
  def credentials(opts \\ []) when is_list(opts) do
    opts
    |> credential_sources()
    |> List.wrap()
    |> Enum.find_value(%{}, &resolve_credentials(&1, opts))
  end

  @doc """
  Resolves the access key id.

  ## Examples

      AwsSDK.Config.access_key_id(access_key_id: "AKIA1EXAMPLE")
      #=> "AKIA1EXAMPLE"

      # Unresolvable from any source.
      AwsSDK.Config.access_key_id()
      #=> nil
  """
  @spec access_key_id(keyword) :: String.t() | nil
  def access_key_id(opts \\ []), do: opts |> credentials() |> Map.get(:access_key_id)

  @doc """
  Resolves the secret access key.

  ## Examples

      AwsSDK.Config.secret_access_key(profile: "dev")
      #=> "wJalrXUtnFEMI/K7MDENG/bPxRfiCY"
  """
  @spec secret_access_key(keyword) :: String.t() | nil
  def secret_access_key(opts \\ []), do: opts |> credentials() |> Map.get(:secret_access_key)

  @doc """
  Resolves the security (session) token.

  ## Examples

      AwsSDK.Config.security_token(profile: "dev")
      #=> "IQoJb3JpZ2luX2VjEJr..."

      # Long-lived IAM user keys carry no session token.
      AwsSDK.Config.security_token(access_key_id: "AKIA1EXAMPLE", secret_access_key: "SK")
      #=> nil
  """
  @spec security_token(keyword) :: String.t() | nil
  def security_token(opts \\ []), do: opts |> credentials() |> Map.get(:security_token)

  @doc """
  Resolves the region chain. Falls back to `\"us-east-1\"` because the
  built-in chain ends with that literal.

  ## Examples

      AwsSDK.Config.region(region: "eu-west-1")
      #=> "eu-west-1"

      # Falls back to the app env, then AWS_REGION / AWS_DEFAULT_REGION,
      # then the shared config profile, then "us-east-1".
      AwsSDK.Config.region()
      #=> "us-east-1"
  """
  @spec region(keyword) :: String.t()
  def region(opts \\ []), do: region(opts, credentials(opts))

  @doc """
  Resolves the region against an already-resolved credential set,
  avoiding a second chain walk. Used by `new/1`.

  ## Examples

      creds = AwsSDK.Config.credentials(profile: "dev")
      AwsSDK.Config.region([], creds)
      #=> "eu-west-1"

  Same chain as `region/1`, but reads the profile's region off an
  already-resolved credential map instead of walking the source chain a
  second time.
  """
  @spec region(keyword, map) :: String.t()
  def region(opts, creds) when is_list(opts) and is_map(creds) do
    with nil <- present(opts[:region]),
         nil <- resolve_region(Application.get_env(@app, :region)),
         nil <- present(creds[:region]) do
      resolve_region(@region)
    end
  end

  @doc """
  Returns the merged sandbox keyword list. Defaults are overlaid with
  the `:aws_sdk` `:sandbox` app-env entry, then with `opts[:sandbox]`.

  ## Examples

      AwsSDK.Config.sandbox()
      #=> [enabled: false]

      AwsSDK.Config.sandbox(sandbox: [enabled: true])
      #=> [enabled: true]
  """
  @spec sandbox(keyword) :: keyword
  def sandbox(opts \\ []) do
    @sandbox
    |> Keyword.merge(Application.get_env(@app, :sandbox, []))
    |> Keyword.merge(Keyword.get(opts, :sandbox, []))
  end

  # -- credential chain --------------------------------------------------------

  # Explicit per-call keys short-circuit the chain, then `:profile`,
  # then an app-env chain override, then the built-in default.
  defp credential_sources(opts) do
    case explicit_credentials(opts) do
      nil -> profile_source(opts) || Application.get_env(@app, :credentials, @credentials)
      creds -> creds
    end
  end

  defp explicit_credentials(opts) do
    case {present(opts[:access_key_id]), present(opts[:secret_access_key])} do
      {nil, nil} ->
        nil

      {key, secret} when is_binary(key) and is_binary(secret) ->
        %{
          access_key_id: key,
          secret_access_key: secret,
          security_token: present(opts[:security_token])
        }

      {key, _secret} ->
        raise ArgumentError,
              ":access_key_id and :secret_access_key must be given together — got only " <>
                if(key, do: ":access_key_id", else: ":secret_access_key") <>
                ". Pairing an explicit key with a secret resolved from elsewhere " <>
                "produces a signature AWS rejects."
    end
  end

  defp profile_source(opts) do
    case present(opts[:profile]) do
      profile when is_binary(profile) -> {:awscli, profile}
      nil -> nil
    end
  end

  defp resolve_credentials(:env, _opts) do
    complete(%{
      access_key_id: present(System.get_env("AWS_ACCESS_KEY_ID")),
      secret_access_key: present(System.get_env("AWS_SECRET_ACCESS_KEY")),
      security_token: present(System.get_env("AWS_SESSION_TOKEN"))
    })
  end

  defp resolve_credentials(:app_env, _opts) do
    complete(%{
      access_key_id: present(Application.get_env(@app, :access_key_id)),
      secret_access_key: present(Application.get_env(@app, :secret_access_key)),
      security_token: present(Application.get_env(@app, :security_token))
    })
  end

  defp resolve_credentials({:awscli, {:system, env_var}}, opts) do
    case present(System.get_env(env_var)) do
      nil -> nil
      profile -> resolve_credentials({:awscli, profile}, opts)
    end
  end

  defp resolve_credentials({:awscli, profile}, opts) do
    ttl = Keyword.get(opts, :profile_ttl_seconds, @default_profile_ttl_seconds)

    {:awscli, profile}
    |> AuthCache.get(Keyword.put(opts, :ttl_seconds, ttl))
    |> from_cache()
  end

  defp resolve_credentials(:instance_role, opts) do
    :aws_instance_auth |> AuthCache.get(opts) |> from_cache()
  end

  defp resolve_credentials(:ecs_task_role, opts) do
    :aws_ecs_auth |> AuthCache.get(opts) |> from_cache()
  end

  defp resolve_credentials(creds, _opts) when is_map(creds), do: complete(creds)

  defp resolve_credentials(_value, _opts), do: nil

  defp from_cache({:ok, creds}) when is_map(creds), do: complete(creds)
  defp from_cache({:error, _reason}), do: nil

  # A source counts only when it produced both halves of a usable pair.
  # Anything less falls through to the next source rather than
  # contributing a fragment to a mixed set.
  defp complete(%{access_key_id: key, secret_access_key: secret} = creds)
       when is_binary(key) and is_binary(secret) do
    creds
  end

  defp complete(_partial), do: nil

  # -- region chain ------------------------------------------------------------

  defp resolve_region(nil), do: nil
  defp resolve_region(value) when is_list(value), do: Enum.find_value(value, &resolve_region/1)
  defp resolve_region(value) when is_binary(value), do: present(value)
  defp resolve_region({:system, env_var}), do: present(System.get_env(env_var))
  defp resolve_region(_value), do: nil

  # -- shared ------------------------------------------------------------------

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present(value) when is_binary(value), do: trim_or_nil(String.trim(value))
  defp present(value), do: value

  defp trim_or_nil(""), do: nil
  defp trim_or_nil(value), do: value
end
