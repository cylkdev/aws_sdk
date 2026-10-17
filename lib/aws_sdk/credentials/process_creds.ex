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

  alias AwsSDK.Credentials.Redact
  alias AwsSDK.Error

  @type creds :: %{
          access_key_id: String.t(),
          secret_access_key: String.t(),
          security_token: String.t() | nil,
          expires_at: DateTime.t() | nil,
          source: atom,
          process_output: map,
          process: map
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
      #=>    source: :credential_process,
      #=>    process_output: %{"Version" => 1, "AccessKeyId" => "ASIA1EXAMPLE", ...},
      #=>    process: %{command: "aws-vault", stdout: "{...}", stderr: "", exit_status: 0, ...}
      #=>  }}

      AwsSDK.Credentials.ProcessCreds.run("false", :credential_process)
      #=> {:error, %ErrorMessage{code: :internal_server_error, details: %{kind: :credential_process_failed, process: %{command: "false", stderr: "", exit_status: 1, args: []}}}}

  Runs the command and reads AWS's documented JSON contract from stdout
  (`Version`, `AccessKeyId`, `SecretAccessKey`, `SessionToken`,
  `Expiration`). A non-zero exit or unparseable output is an error, never a
  partial credential.
  """
  @spec run(String.t(), atom) :: {:ok, creds} | {:error, ErrorMessage.t()}
  def run(command, source) when is_binary(command) and is_atom(source) do
    [bin | args] = OptionParser.split(command)

    case cmd(bin, args) do
      %{exit_status: 0} = result -> parse(result, source)
      result -> {:error, Error.new(:credential_process_failed, %{process: Redact.strip(result)})}
    end
  rescue
    exception ->
      {:error, Error.new(:credential_process_failed, %{command: command, exception: exception})}
  end

  @doc """
  Runs `bin` with `args` and returns stdout and stderr as separate facts.

  `System.cmd/3` can only capture stderr by merging it into stdout, so the
  command runs under `sh` with stderr redirected to a temporary file, which
  is read back and removed. `:stderr` is a `:file_error` error if that
  file could not be read. Requires a POSIX `sh`.

  ## Examples

      AwsSDK.Credentials.ProcessCreds.cmd("ls", ["/nope"])
      #=> %{command: "ls", args: ["/nope"], stdout: "",
      #=>   stderr: "ls: /nope: No such file or directory\n", exit_status: 1}
  """
  @spec cmd(String.t(), [String.t()]) :: %{
          command: String.t(),
          args: [String.t()],
          stdout: binary,
          stderr: binary | {:error, ErrorMessage.t()},
          exit_status: non_neg_integer
        }
  def cmd(bin, args) do
    stderr_path =
      Path.join(System.tmp_dir!(), "aws_sdk_stderr_#{System.unique_integer([:positive])}")

    try do
      {stdout, status} =
        System.cmd("sh", ["-c", ~s(exec "$0" "$@" 2>"$AWS_SDK_STDERR_PATH"), bin | args],
          env: [{"AWS_SDK_STDERR_PATH", stderr_path}]
        )

      stderr =
        case File.read(stderr_path) do
          {:ok, contents} ->
            contents

          {:error, reason} ->
            {:error, Error.new(:file_error, %{reason: reason, path: stderr_path})}
        end

      %{command: bin, args: args, stdout: stdout, stderr: stderr, exit_status: status}
    after
      File.rm(stderr_path)
    end
  end

  defp parse(result, source) do
    case decode_json(result.stdout) do
      {:ok, %{"Version" => 1} = body} ->
        build(body, result, source)

      {:ok, body} ->
        {:error,
         Error.new(:credential_process_invalid, %{
           version: body["Version"],
           process: Redact.strip(result)
         })}

      {:error, error} ->
        {:error,
         Error.new(:credential_process_invalid, %{error: error, process: Redact.strip(result)})}
    end
  end

  defp decode_json(binary) do
    {:ok, :json.decode(binary)}
  rescue
    exception -> {:error, Error.new(:invalid_json, %{exception: exception})}
  end

  defp build(body, result, source) do
    with {:ok, ak} <- fetch_string(body, "AccessKeyId", result),
         {:ok, sk} <- fetch_string(body, "SecretAccessKey", result) do
      {:ok,
       %{
         access_key_id: ak,
         secret_access_key: sk,
         security_token: optional_string(body, "SessionToken"),
         expires_at: parse_expiration(body["Expiration"]),
         source: source,
         # The process's full JSON output, including `Version` and any
         # fields beyond the documented ones.
         process_output: Redact.strip(body),
         # The raw run: command, args, stdout, stderr and exit status.
         process: Redact.strip(result)
       }}
    end
  end

  defp fetch_string(body, key, result) do
    case Map.get(body, key) do
      v when is_binary(v) and v !== "" ->
        {:ok, v}

      _ ->
        {:error,
         Error.new(:credential_process_invalid, %{
           missing_field: key,
           process: Redact.strip(result)
         })}
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
