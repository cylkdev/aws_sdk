defmodule AwsSDK.Credentials.Providers.ECS do
  @moduledoc """
  Resolves credentials from the ECS container-credentials endpoint,
  used by tasks running on ECS/Fargate and by EKS when
  IAM-for-service-accounts (IRSA) isn't configured.

  Looks at two env vars:

    * `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` — a path that is joined
      to `http://169.254.170.2` (the ECS agent's link-local address).
    * `AWS_CONTAINER_CREDENTIALS_FULL_URI` — a full URL. Loopback
      (`127.0.0.1`, `localhost`) and the link-local 169.254.170.2
      address are allowed over plain HTTP; anything else must be HTTPS
      to match the AWS SDK's guardrails.

  When `AWS_CONTAINER_AUTHORIZATION_TOKEN` is set, its value is sent as
  the `Authorization` header.
  """

  alias AwsSDK.HTTP

  @ecs_host "169.254.170.2"

  # The EKS Pod Identity Agent listens on these; without them a Pod Identity
  # setup was silently skipped rather than reported.
  @eks_pod_identity_hosts ["169.254.170.23", "[fd00:ec2::23]", "fd00:ec2::23"]

  @doc false
  def resolve(opts) do
    cond do
      uri = relative_uri() -> fetch(uri, opts)
      uri = full_uri() -> fetch(uri, opts)
      true -> :skip
    end
  end

  defp relative_uri do
    case System.get_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI") do
      nil -> nil
      "" -> nil
      path -> "http://#{@ecs_host}" <> ensure_leading_slash(path)
    end
  end

  defp full_uri do
    case System.get_env("AWS_CONTAINER_CREDENTIALS_FULL_URI") do
      nil -> nil
      "" -> nil
      url -> if allowed_full_uri?(url), do: url, else: nil
    end
  end

  defp allowed_full_uri?(url) do
    case URI.parse(url) do
      %URI{scheme: "https"} ->
        true

      %URI{scheme: "http", host: "localhost"} ->
        true

      %URI{scheme: "http", host: @ecs_host} ->
        true

      %URI{scheme: "http", host: host} ->
        host in @eks_pod_identity_hosts or loopback?(host)

      _ ->
        false
    end
  end

  defp ensure_leading_slash("/" <> _ = path), do: path
  defp ensure_leading_slash(path), do: "/" <> path

  defp fetch(url, opts) do
    headers = auth_headers() ++ [{"accept", "application/json"}]

    case HTTP.get(url, headers, Keyword.get(opts, :http, [])) do
      {:ok, %{status_code: 200, body: body}} -> decode(body)
      {:ok, %{status_code: status, body: body}} -> {:error, {:ecs_http_error, status, body}}
      {:error, %{reason: reason}} -> {:error, {:ecs_transport_error, reason}}
    end
  end

  # EKS Pod Identity supplies the token through a file that is rotated in
  # place, alongside AWS_CONTAINER_CREDENTIALS_FULL_URI; the plain env var is
  # the ECS form. The file takes precedence, matching the SDKs.
  defp auth_headers do
    case token_from_file() || present(System.get_env("AWS_CONTAINER_AUTHORIZATION_TOKEN")) do
      nil -> []
      token -> [{"authorization", token}]
    end
  end

  defp token_from_file do
    with path when is_binary(path) <-
           present(System.get_env("AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE")),
         {:ok, contents} <- File.read(path) do
      present(String.trim(contents))
    else
      _ -> nil
    end
  end

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present(value), do: value

  # The whole 127.0.0.0/8 range and IPv6 loopback are link-local to the pod,
  # not just 127.0.0.1.
  defp loopback?("::1"), do: true
  defp loopback?("[::1]"), do: true

  defp loopback?("127." <> _ = host) do
    case :inet.parse_ipv4_address(String.to_charlist(host)) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp loopback?(_), do: false

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
           source: :ecs
         }}

      _ ->
        {:error, {:ecs_invalid_response, decoded}}
    end
  rescue
    err -> {:error, {:ecs_invalid_json, Exception.message(err)}}
  end

  defp parse_expiration(nil), do: nil

  defp parse_expiration(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
