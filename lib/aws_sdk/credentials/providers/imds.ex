defmodule AwsSDK.Credentials.Providers.IMDS do
  @moduledoc """
  Resolves credentials from the EC2 Instance Metadata Service (IMDSv2).

  Two-step handshake:

    1. `PUT /latest/api/token` with `x-aws-ec2-metadata-token-ttl-seconds`
       to obtain a session token.
    2. `GET /latest/meta-data/iam/security-credentials/<role>` with
       `x-aws-ec2-metadata-token: <token>` to fetch the JSON document.

  Disabled when `AWS_EC2_METADATA_DISABLED=true` is set. Connect
  timeout is kept tight (1 second) because IMDS is the last resort in
  the chain and a hung metadata call would otherwise stall every call
  on a non-EC2 host.
  """

  alias AwsSDK.HTTP

  @endpoint "http://169.254.169.254"
  @token_ttl "21600"
  @connect_timeout 1_000
  @request_timeout 1_000

  @doc false
  def resolve(opts) do
    if disabled?() do
      :skip
    else
      fetch(opts)
    end
  end

  defp disabled? do
    case System.get_env("AWS_EC2_METADATA_DISABLED") do
      nil -> false
      value -> String.downcase(String.trim(value)) === "true"
    end
  end

  defp fetch(opts) do
    endpoint = opts[:endpoint] || @endpoint
    http = http_opts(opts)

    with {:ok, token} <- get_token(endpoint, http),
         {:ok, role} <- get_role(endpoint, token, http),
         {:ok, body} <- get_credentials(endpoint, token, role, http) do
      decode(body)
    end
  end

  defp http_opts(opts) do
    user = Keyword.get(opts, :http, [])

    user
    |> Keyword.put_new(:connect_timeout, @connect_timeout)
    |> Keyword.put_new(:request_timeout, @request_timeout)
  end

  defp get_token(endpoint, http) do
    url = endpoint <> "/latest/api/token"
    headers = [{"x-aws-ec2-metadata-token-ttl-seconds", @token_ttl}]

    case HTTP.request(:put, url, "", headers, http) do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: status}} -> {:error, {:imds_token_error, status}}
      {:error, %{reason: reason}} -> {:error, {:imds_transport_error, reason}}
    end
  end

  defp get_role(endpoint, token, http) do
    url = endpoint <> "/latest/meta-data/iam/security-credentials/"
    headers = [{"x-aws-ec2-metadata-token", token}]

    case HTTP.get(url, headers, http) do
      {:ok, %{status_code: 200, body: body}} -> {:ok, first_role(body)}
      {:ok, %{status_code: 404}} -> {:error, :imds_no_role}
      {:ok, %{status_code: status}} -> {:error, {:imds_role_error, status}}
      {:error, %{reason: reason}} -> {:error, {:imds_transport_error, reason}}
    end
  end

  defp get_credentials(endpoint, token, role, http) do
    url = endpoint <> "/latest/meta-data/iam/security-credentials/" <> role
    headers = [{"x-aws-ec2-metadata-token", token}]

    case HTTP.get(url, headers, http) do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: status, body: body}} -> {:error, {:imds_http_error, status, body}}
      {:error, %{reason: reason}} -> {:error, {:imds_transport_error, reason}}
    end
  end

  defp decode(body) do
    decoded = :json.decode(body)

    case decoded do
      %{"AccessKeyId" => ak, "SecretAccessKey" => sk} = payload ->
        {:ok,
         %{
           access_key_id: ak,
           secret_access_key: sk,
           security_token: payload["Token"],
           expires_at: parse_expiration(payload["Expiration"]),
           source: :imds
         }}

      _ ->
        {:error, {:imds_invalid_response, decoded}}
    end
  rescue
    err -> {:error, {:imds_invalid_json, Exception.message(err)}}
  end

  defp parse_expiration(nil), do: nil

  defp parse_expiration(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  # The role listing is LF-separated. With more than one role attached,
  # trimming the whole blob produced a multi-line "role name"; the SDKs take
  # the first entry.
  defp first_role(body) do
    body
    |> String.split(~r/\r?\n/, trim: true)
    |> List.first("")
    |> String.trim()
  end
end
