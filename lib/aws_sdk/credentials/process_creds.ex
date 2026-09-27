defmodule AwsSDK.Credentials.ProcessCreds do
  @moduledoc """
  Shared command runner and parser for the
  [credential_process JSON shape](https://docs.aws.amazon.com/cli/latest/topic/config-vars.html#sourcing-credentials-from-external-processes):

      {
        "Version": 1,
        "AccessKeyId": "...",
        "SecretAccessKey": "...",
        "SessionToken": "...",
        "Expiration": "2026-04-16T19:00:00Z"
      }

  Used by both `AwsSDK.Credentials.Providers.CredentialProcess` (explicit
  `credential_process` key in the profile) and
  `AwsSDK.Credentials.Providers.LoginSession` (`aws login`-populated
  profiles, which are resolved by shelling out to
  `aws configure export-credentials --format process`).

  The `source` argument tags the resulting credential map so callers
  downstream can tell which provider produced the credentials.
  """

  @type creds :: %{
          access_key_id: String.t(),
          secret_access_key: String.t(),
          security_token: String.t() | nil,
          expires_at: DateTime.t() | nil,
          source: atom
        }

  @doc """
  Runs `command` and parses the JSON it prints on stdout. `source` is
  the atom stamped onto the resulting credential map.

  ## Examples

      AwsSDK.Credentials.ProcessCreds.run("aws-vault exec dev --json", :credential_process)
      #=> {:ok,
      #=>  %{
      #=>    access_key_id: "ASIA1EXAMPLE",
      #=>    secret_access_key: "...",
      #=>    security_token: "IQoJb3JpZ2luX2VjEJr...",
      #=>    expires_at: ~U[2026-01-01 01:00:00Z],
      #=>    source: :credential_process
      #=>  }}

      AwsSDK.Credentials.ProcessCreds.run("false", :credential_process)
      #=> {:error, :no_credentials}

  Runs the command and reads AWS's documented JSON contract from stdout
  (`Version`, `AccessKeyId`, `SecretAccessKey`, `SessionToken`,
  `Expiration`). A non-zero exit or unparseable output is an error, never a
  partial credential.
  """
  @spec run(String.t(), atom) :: {:ok, creds} | {:error, term}
  def run(command, source) when is_binary(command) and is_atom(source) do
    [bin | args] = OptionParser.split(command)

    case System.cmd(bin, args, stderr_to_stdout: true) do
      {output, 0} -> parse(output, source)
      {output, status} -> {:error, {:credential_process_failed, status, String.trim(output)}}
    end
  rescue
    err -> {:error, {:credential_process_failed, :exception, Exception.message(err)}}
  end

  defp parse(output, source) do
    case decode_json(output) do
      {:ok, %{"Version" => 1} = body} ->
        build(body, source)

      {:ok, body} ->
        {:error, {:credential_process_invalid, {:unsupported_version, body["Version"]}}}

      {:error, reason} ->
        {:error, {:credential_process_invalid, reason}}
    end
  end

  defp decode_json(binary) do
    {:ok, :json.decode(binary)}
  rescue
    err -> {:error, Exception.message(err)}
  end

  defp build(body, source) do
    with {:ok, ak} <- fetch_string(body, "AccessKeyId"),
         {:ok, sk} <- fetch_string(body, "SecretAccessKey") do
      {:ok,
       %{
         access_key_id: ak,
         secret_access_key: sk,
         security_token: optional_string(body, "SessionToken"),
         expires_at: parse_expiration(body["Expiration"]),
         source: source
       }}
    end
  end

  defp fetch_string(body, key) do
    case Map.get(body, key) do
      v when is_binary(v) and v !== "" -> {:ok, v}
      _ -> {:error, {:missing_field, key}}
    end
  end

  defp optional_string(body, key) do
    case Map.get(body, key) do
      v when is_binary(v) and v !== "" -> v
      _ -> nil
    end
  end

  defp parse_expiration(nil), do: nil

  defp parse_expiration(binary) when is_binary(binary) do
    case DateTime.from_iso8601(binary) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
