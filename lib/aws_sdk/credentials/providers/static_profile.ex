defmodule AwsSDK.Credentials.Providers.StaticProfile do
  @moduledoc """
  Resolves static `aws_access_key_id` / `aws_secret_access_key` /
  `aws_session_token` keys from the shared profile (merged from
  `~/.aws/config` and `~/.aws/credentials`).

  Skips profiles that carry SSO or `credential_process` keys: those
  are handled by their dedicated providers, and returning `:skip` here
  lets the chain continue to them.
  """

  alias AwsSDK.Credentials.Profile

  @sso_indicators ~w(sso_session sso_start_url credential_process role_arn)

  @doc false
  def resolve(opts) do
    profile_name = opts[:profile] || Profile.default()

    case Profile.load(profile_name, opts) do
      nil ->
        :skip

      profile ->
        if Enum.any?(@sso_indicators, &Map.has_key?(profile, &1)) do
          :skip
        else
          from_profile(profile)
        end
    end
  end

  defp from_profile(profile) do
    ak = profile["aws_access_key_id"]
    sk = profile["aws_secret_access_key"]
    st = profile["aws_session_token"]

    if is_binary(ak) and is_binary(sk) do
      {:ok,
       %{
         access_key_id: ak,
         secret_access_key: sk,
         security_token: present(st),
         expires_at: nil,
         source: :profile
       }}
    else
      :skip
    end
  end

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present(s) when is_binary(s), do: s
end
