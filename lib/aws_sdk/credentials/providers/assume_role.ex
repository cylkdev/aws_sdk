defmodule AwsSDK.Credentials.Providers.AssumeRole do
  @moduledoc """
  Resolves credentials from a profile that carries a `role_arn`.

  The profile must identify a `source_profile` (or `credential_source`,
  not yet supported) to produce the caller identity used to sign the
  `AssumeRole` request. The source profile is resolved through
  `AwsSDK.AuthCache` under its own `{:awscli, name}` key, so it is cached
  and single-flighted like any other profile instead of being re-minted
  on every refresh of the assumed role.

  Session name defaults to `aws-elixir-<unix-ts>` and can be overridden
  via `role_session_name` on the profile.

  STS is invoked during credential resolution, so the request is built
  via `AwsSDK.STS.assume_role/4`, which accepts pre-resolved source
  credentials and bypasses the normal credential-chain lookup that
  `AwsSDK.STS.get_caller_identity/1` and other public operations use.
  """

  alias AwsSDK.AuthCache
  alias AwsSDK.Credentials.Profile

  @default_duration_seconds 3_600

  @doc false
  def resolve(opts) do
    profile_name = opts[:profile] || Profile.default()

    case Profile.load(profile_name, opts) do
      nil ->
        :skip

      profile ->
        resolve_with_profile(profile, opts)
    end
  end

  defp resolve_with_profile(profile, opts) do
    role_arn = profile["role_arn"]
    source = profile["source_profile"]

    cond do
      is_nil(role_arn) ->
        :skip

      is_nil(source) ->
        {:error, :assume_role_missing_source_profile}

      # A profile naming itself as its own source would re-enter the
      # AuthCache fetch for a key already in flight and never resolve.
      source === (opts[:profile] || Profile.default()) ->
        {:error, :assume_role_self_reference}

      true ->
        assume(role_arn, source, profile, opts)
    end
  end

  defp assume(role_arn, source_profile, profile, opts) do
    region = profile["region"] || "us-east-1"

    base_params = %{
      role_arn: role_arn,
      role_session_name: session_name(profile),
      duration_seconds: duration(profile)
    }

    params = maybe_put(base_params, :external_id, profile["external_id"])

    with {:ok, source} <- AuthCache.get({:awscli, source_profile}, source_opts(opts)),
         {:ok, result} <- AwsSDK.STS.assume_role(params, source, region, opts) do
      {:ok,
       %{
         access_key_id: result.credentials.access_key_id,
         secret_access_key: result.credentials.secret_access_key,
         security_token: result.credentials.session_token,
         expires_at: result.credentials.expiration,
         source: :sts
       }}
    end
  end

  # The source profile is a cache key of its own, so it must not inherit
  # the outer profile's TTL or the test fetcher seam. `:profile` is reset
  # by `Profile.security_credentials/2` from the cache key itself.
  defp source_opts(opts), do: Keyword.drop(opts, [:ttl_seconds, :fetcher])

  defp session_name(profile) do
    profile["role_session_name"] || "aws-elixir-#{System.system_time(:second)}"
  end

  defp duration(profile) do
    case profile["duration_seconds"] do
      nil -> @default_duration_seconds
      seconds when is_binary(seconds) -> String.to_integer(seconds)
      seconds when is_integer(seconds) -> seconds
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
