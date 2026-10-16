defmodule AwsSDK.Credentials.Secrets do
  @moduledoc """
  Removes secret values from the raw facts credential providers keep.

  Providers return the credential fields the signer reads at the top level,
  and nest everything else they received (STS responses, IMDS/ECS/SSO
  responses, profile files, process output, the credential chain) under
  their own keys. Those nested facts are cached by `AwsSDK.AuthCache` and
  can end up in error terms, logs and crash reports, so every key that
  holds a secret is removed from them before they are kept.
  """

  @secret_keys MapSet.new([
                 "secret_access_key",
                 "secretaccesskey",
                 "aws_secret_access_key",
                 "session_token",
                 "sessiontoken",
                 "aws_session_token",
                 "security_token",
                 "token",
                 "access_token",
                 "accesstoken",
                 "refresh_token",
                 "refreshtoken",
                 "client_secret",
                 "clientsecret",
                 "x_aws_ec2_metadata_token",
                 "x-aws-ec2-metadata-token",
                 "stdout"
               ])

  @doc """
  Returns `term` with every map entry whose key names a secret removed,
  recursing through maps, lists and tuples.

  Keys match by name regardless of case or whether they are atoms or
  strings, so `"SecretAccessKey"`, `:secret_access_key` and
  `"aws_secret_access_key"` are all removed. A credential process's raw
  `:stdout` is removed too, because it is the credentials JSON.

  ## Examples

      AwsSDK.Credentials.Secrets.strip(%{
        "AccessKeyId" => "AKIA...",
        "SecretAccessKey" => "wJal...",
        "Expiration" => "2026-10-15T12:00:00Z"
      })
      #=> %{"AccessKeyId" => "AKIA...", "Expiration" => "2026-10-15T12:00:00Z"}
  """
  @spec strip(term) :: term
  def strip(%_{} = struct), do: struct

  def strip(map) when is_map(map) do
    for {key, value} <- map, not secret_key?(key), into: %{} do
      {key, strip(value)}
    end
  end

  def strip(list) when is_list(list) do
    Enum.map(list, fn
      {key, value} -> if secret_key?(key), do: {key, nil}, else: {key, strip(value)}
      other -> strip(other)
    end)
  end

  def strip(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> strip() |> List.to_tuple()
  end

  def strip(other), do: other

  defp secret_key?(key) when is_atom(key), do: secret_key?(Atom.to_string(key))

  defp secret_key?(key) when is_binary(key),
    do: MapSet.member?(@secret_keys, String.downcase(key))

  defp secret_key?(_key), do: false
end
