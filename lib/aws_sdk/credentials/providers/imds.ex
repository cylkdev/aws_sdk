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

  alias AwsSDK.Credentials.Redact
  alias AwsSDK.Error
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

    with {:ok, token_resp} <- get_token(endpoint, http),
         {:ok, roles_resp} <- get_role(endpoint, token_resp.body, http),
         role = first_role(roles_resp.body),
         {:ok, creds_resp} <- get_credentials(endpoint, token_resp.body, role, http),
         {:ok, creds} <- decode(creds_resp.body) do
      # The signer reads the top-level keys. Every IMDS response is kept
      # under `:imds`, one key per call: body as received (the credentials
      # document JSON-decoded) plus its headers.
      {:ok,
       Map.put(
         creds,
         :imds,
         Redact.strip(%{
           token: token_resp,
           security_credentials: roles_resp,
           role_credentials: %{creds_resp | body: :json.decode(creds_resp.body)}
         })
       )}
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
      {:ok, %{status_code: 200, body: body, headers: h}} ->
        {:ok, %{body: body, headers: h}}

      {:ok, %{status_code: status, body: body, headers: h}} ->
        {:error, Error.new(:http_error, %{status: status, response: body, headers: h, url: url})}

      {:error, _} = error ->
        error
    end
  end

  defp get_role(endpoint, token, http) do
    url = endpoint <> "/latest/meta-data/iam/security-credentials/"
    headers = [{"x-aws-ec2-metadata-token", token}]

    case HTTP.get(url, headers, http) do
      {:ok, %{status_code: 200, body: body, headers: h}} ->
        {:ok, %{body: body, headers: h}}

      {:ok, %{status_code: status, body: body, headers: h}} ->
        {:error, Error.new(:http_error, %{status: status, response: body, headers: h, url: url})}

      {:error, _} = error ->
        error
    end
  end

  defp get_credentials(endpoint, token, role, http) do
    url = endpoint <> "/latest/meta-data/iam/security-credentials/" <> role
    headers = [{"x-aws-ec2-metadata-token", token}]

    case HTTP.get(url, headers, http) do
      {:ok, %{status_code: 200, body: body, headers: h}} ->
        {:ok, %{body: body, headers: h}}

      {:ok, %{status_code: status, body: body, headers: h}} ->
        {:error, Error.new(:http_error, %{status: status, response: body, headers: h, url: url})}

      {:error, _} = error ->
        error
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
        {:error, Error.new(:unexpected_response, %{response: Redact.strip(decoded)})}
    end
  rescue
    exception -> {:error, Error.new(:invalid_json, %{exception: exception})}
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
