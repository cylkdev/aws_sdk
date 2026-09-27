defmodule AwsSDK.Client do
  @moduledoc """
  Shared SigV4 request dispatcher for `AwsSDK.Operation` structs.

  Owns the parts that are identical across EventBridge, Logs,
  Organizations, Identity Center, IAM, STS, and S3:

    * SigV4 signing via `AwsSDK.Signer.sign/5`,
    * HTTP dispatch via `AwsSDK.HTTP` (buffered, stream-upload, or
      stream-download depending on struct fields),
    * status-code branching into `{:ok, resp}` for 2xx,
      `{:error, {:http_error, status, body}}` otherwise, and
      `{:error, reason}` on transport failure,
    * credential / endpoint / sandbox resolution driven by a per-service
      opts namespace (`:s3`, `:iam`, `:events`, `:logs`,
      `:organizations`, `:identity_center`).

  Callers build a populated Operation struct in their service facade
  (`AwsSDK.EventBridge`, `AwsSDK.S3`, …) and hand it to `request/1`,
  which wraps `execute/1` (the raw transport seam) with error mapping. The
  struct is the whole contract between facade and dispatcher: body
  is already encoded, headers are already populated, URL is already
  composed.

  Per-service facades contribute only the parts that genuinely differ
  across AWS protocols: body encoding (JSON vs form-urlencoded vs
  passthrough), request headers (`X-Amz-Target` for JSON 1.1, `Action`
  in body for Query, per-operation for REST/XML), URL composition
  (virtual-hosted addressing is S3-only), and response body decoding.
  """

  alias AwsSDK.{Config, HTTP, Signer}
  alias AwsSDK.Credentials.Profile

  @type method :: :get | :post | :put | :delete | :head
  @type header :: {String.t(), String.t()}
  @type body :: iodata | Enumerable.t()

  @type response :: %{
          status_code: non_neg_integer,
          headers: [header],
          body: binary
        }

  @type stream_response :: %{
          status_code: non_neg_integer,
          headers: [header],
          body_stream: Enumerable.t()
        }

  @doc """
  Issues a SigV4-signed HTTP request from a populated Operation
  struct.

  The argument can be any struct carrying the SigV4 fields — in
  practice an `AwsSDK.Operation`.

  ## Required struct fields

    * `:method` — `:get | :post | :put | :delete | :head`
    * `:url` — fully-built URL string. The facade owns URL
      composition (path, query params, virtual-hosted addressing).
    * `:headers` — list of `{name, value}` tuples to include in the
      SigV4 canonical request (content-type, x-amz-target,
      x-amz-copy-source, range, ...).
    * `:body` — binary / iodata for buffered requests, or an
      `Enumerable.t()` when `:stream_upload` is `true`.
    * `:service` — SigV4 service name (e.g. `"s3"`, `"events"`).
    * `:region` — region string for the signing scope.
    * `:access_key_id`, `:secret_access_key` — signing credentials.

  ## Optional struct fields

    * `:security_token` — session token appended as
      `x-amz-security-token`.
    * `:payload_hash` — signer override for
      `x-amz-content-sha256`. Pass `"UNSIGNED-PAYLOAD"` for S3
      streaming uploads and presigned URLs.
    * `:stream_upload` (default `false`) — body is an `Enumerable`;
      dispatch via `HTTP.stream_upload/5`.
    * `:stream_response` (default `false`) — return `body_stream`
      instead of a buffered body; dispatch via
      `HTTP.stream_download/3`.
    * `:http` — opts forwarded to `AwsSDK.HTTP` (`:connect_timeout`,
      `:request_timeout`).
    * `:now` — override `DateTime.utc_now/0` for deterministic
      signatures in tests.

  ## Examples

      {:ok, op} = AwsSDK.EC2.build_operation("DescribeTags", %{}, access_key_id: "AK", secret_access_key: "SK")

      AwsSDK.Client.execute(op)
      #=> {:ok, %{status: 200, body: "<DescribeTagsResponse>...", headers: [...]}}

      # Non-2xx is an error at this layer, unlike AwsSDK.HTTP.
      AwsSDK.Client.execute(op)
      #=> {:error, {:http_error, 403, "<ErrorResponse>...</ErrorResponse>"}}

      AwsSDK.Client.execute(op)
      #=> {:error, %Mint.TransportError{reason: :nxdomain}}

  The three shapes above are exactly what `request/1` pattern-matches on.
  """
  @spec execute(struct) ::
          {:ok, response}
          | {:ok, stream_response}
          | {:error, {:http_error, non_neg_integer, binary}}
          | {:error, term}
  def execute(%_{} = op) do
    method = op.method
    url = op.url
    headers = op.headers
    body = Map.get(op, :body, "")
    stream_upload? = Map.get(op, :stream_upload, false)
    stream_response? = Map.get(op, :stream_response, false)
    http_opts = Map.get(op, :http, []) || []

    # A streamed body is never hashed, so signing SHA256("") would sign
    # something the request does not send. `AwsSDK.S3` pairs `:stream_upload` with
    # an explicit UNSIGNED-PAYLOAD hash; enforce it here so no other caller can
    # get the pairing wrong.
    creds =
      op
      |> build_creds()
      |> then(fn c ->
        if stream_upload?, do: Map.put_new(c, :payload_hash, "UNSIGNED-PAYLOAD"), else: c
      end)

    signing_body = if stream_upload?, do: "", else: body
    signed_headers = Signer.sign(method, url, headers, signing_body, creds)

    dispatch(method, url, body, signed_headers, stream_upload?, stream_response?, http_opts)
  end

  @doc """
  Executes a signed operation and maps failures to `ErrorMessage` errors.

  This is the library's single status-code contract — 3xx →
  `bad_request`, 4xx → `not_found`, 5xx → `service_unavailable`, transport
  errors → `internal_server_error`. The 4xx/5xx/transport mappings align
  with prior per-service helpers; 3xx handling is now uniform. Success
  passes `execute/1`'s response map (`:status_code`, `:headers`, `:body`,
  and the streaming variants) through untouched. For HTTP failures, `details`
  carries the original `:status` code alongside `:response` so callers can
  special-case specific statuses without losing the shared mapping.
  """
  @spec request(struct) :: {:ok, map} | {:error, ErrorMessage.t()}
  def request(%_{} = op) do
    case execute(op) do
      {:ok, response} ->
        {:ok, response}

      {:error, {:http_error, status_code, response}} when status_code in 300..399 ->
        {:error,
         ErrorMessage.bad_request("redirect not followed.", %{
           status: status_code,
           response: response
         })}

      {:error, {:http_error, status_code, response}} when status_code in 400..499 ->
        {:error,
         ErrorMessage.not_found("resource not found.", %{status: status_code, response: response})}

      {:error, {:http_error, status_code, response}} when status_code >= 500 ->
        {:error,
         ErrorMessage.service_unavailable("service temporarily unavailable", %{
           status: status_code,
           response: response
         })}

      {:error, reason} ->
        {:error, ErrorMessage.internal_server_error("internal server error", %{reason: reason})}
    end
  end

  @doc """
  Resolves the endpoint / credentials / region map for a service.

  `namespace` picks the per-service opts key (e.g. `:s3`, `:events`)
  for endpoint-only overrides (`:scheme`, `:host`, `:port`, plus any
  `extra` keys). Credential keys (`:access_key_id`,
  `:secret_access_key`, `:security_token`, `:region`) are read from
  the flat top-level opts and resolved through `AwsSDK.Config.new/1`.

  `default_host_fn` is a 1-arity function that receives the resolved
  region and returns the default host for the service.

  `extra` is an optional keyword list of additional keys to merge into
  the result from the namespace opts (e.g. S3 passes `[:path_style]`
  so callers can read `config.path_style` directly).

  ## Examples

      AwsSDK.Client.resolve_config(
        :iam,
        [access_key_id: "AKIA1EXAMPLE", secret_access_key: "SK", region: "us-east-1"],
        fn _region -> "iam.amazonaws.com" end
      )
      #=> {:ok,
      #=>  %{
      #=>    scheme: "https",
      #=>    host: "iam.amazonaws.com",
      #=>    port: nil,
      #=>    region: "us-east-1",
      #=>    access_key_id: "AKIA1EXAMPLE",
      #=>    secret_access_key: "SK",
      #=>    security_token: nil
      #=>  }}

  Endpoint overrides come from the service's own opts key, which is how you
  point a service at a local stub:

      AwsSDK.Client.resolve_config(:iam, [iam: [scheme: "http", host: "localhost", port: 4566]], fun)
      #=> {:ok, %{scheme: "http", host: "localhost", port: 4566, ...}}
  """
  @spec resolve_config(atom, keyword, (String.t() -> String.t())) ::
          {:ok, map} | {:error, term}
  @spec resolve_config(atom, keyword, (String.t() -> String.t()), [atom]) ::
          {:ok, map} | {:error, term}
  def resolve_config(namespace, opts, default_host_fn, extra \\ []) do
    {svc_opts, cred_opts} = Keyword.pop(opts, namespace, [])
    {_sandbox_opts, cred_opts} = Keyword.pop(cred_opts, :sandbox, [])

    resolved = Config.new(cred_opts)

    with {:ok, ak, sk, st} <- extract_creds(resolved, cred_opts) do
      region = resolved[:region]
      {scheme, host, port} = resolve_endpoint(svc_opts, default_host_fn, region)

      base = %{
        region: region,
        scheme: scheme,
        host: host,
        port: port,
        access_key_id: ak,
        secret_access_key: sk,
        security_token: st
      }

      {:ok, Enum.reduce(extra, base, fn key, acc -> Map.put(acc, key, svc_opts[key]) end)}
    end
  end

  defp extract_creds(resolved, opts) do
    ak = resolved[:access_key_id]
    sk = resolved[:secret_access_key]

    if is_binary(ak) and is_binary(sk) do
      {:ok, ak, sk, resolved[:security_token]}
    else
      {:error, missing_credentials_error(opts)}
    end
  end

  # When the chain resolved no creds, do a focused diagnostic: load
  # the active profile and, if it exists, surface its key shape and a
  # hint about which provider was expected to handle it. This turns
  # an opaque `:missing_credentials` into an actionable
  # `{:missing_credentials, %{profile: ..., profile_keys: ...,
  # hint: ...}}` whenever the user has a profile configured but no
  # provider could resolve it.
  defp missing_credentials_error(opts) do
    profile_name = opts[:profile] || Profile.default()

    case Profile.load(profile_name, opts) do
      nil ->
        :missing_credentials

      profile when is_map(profile) ->
        {:missing_credentials,
         %{
           profile: profile_name,
           profile_keys: profile |> Map.keys() |> Enum.sort(),
           hint: hint_for(profile)
         }}
    end
  end

  defp hint_for(profile) do
    cond do
      is_binary(profile["sso_session"]) or is_binary(profile["sso_start_url"]) ->
        "profile is configured for SSO; run `aws sso login --profile <name>`"

      is_binary(profile["credential_process"]) ->
        "profile uses credential_process; verify the command exits 0 with a Version 1 JSON body"

      is_binary(profile["login_session"]) ->
        "profile is configured for `aws login`; ensure AWS CLI ≥ 2.32.0 is on PATH and the session is valid"

      is_binary(profile["role_arn"]) ->
        "profile assumes a role; verify the source_profile resolves"

      true ->
        "profile shape not recognized by any provider " <>
          "(no sso_session/sso_start_url/credential_process/login_session/role_arn/aws_access_key_id)"
    end
  end

  @doc """
  Builds a `"{scheme}://{host}{maybe_port}/"` URL for services that
  always POST to root (everyone except S3).

  ## Examples

      AwsSDK.Client.simple_url(%{scheme: "https", host: "iam.amazonaws.com", port: nil})
      #=> "https://iam.amazonaws.com/"

      # A port is only appended when it is not the scheme's default.
      AwsSDK.Client.simple_url(%{scheme: "http", host: "localhost", port: 4566})
      #=> "http://localhost:4566/"
  """
  @spec simple_url(map) :: String.t()
  def simple_url(%{scheme: scheme, host: host, port: port}) do
    "#{scheme}://#{host}#{port_suffix(scheme, port)}/"
  end

  # -- dispatch ---------------------------------------------------------------

  defp dispatch(method, url, body, headers, true, _stream_resp?, http_opts) do
    method
    |> HTTP.stream_upload(url, body, headers, http_opts)
    |> translate_buffered()
  end

  defp dispatch(_method, url, _body, headers, false, true, http_opts) do
    case HTTP.stream_download(url, headers, http_opts) do
      {:ok, %{status_code: status} = resp} when status in 200..299 ->
        {:ok, resp}

      {:ok, %{status_code: status} = resp} ->
        body = resp |> Map.get(:body_stream, []) |> Enum.to_list() |> IO.iodata_to_binary()
        {:error, {:http_error, status, body}}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  defp dispatch(method, url, body, headers, false, false, http_opts) do
    method
    |> HTTP.request(url, body, headers, http_opts)
    |> translate_buffered()
  end

  defp translate_buffered({:ok, %{status_code: status} = resp}) when status in 200..299 do
    {:ok, resp}
  end

  defp translate_buffered({:ok, %{status_code: status, body: body}}) do
    {:error, {:http_error, status, body}}
  end

  defp translate_buffered({:error, %{reason: reason}}) do
    {:error, reason}
  end

  # -- signing creds map ------------------------------------------------------

  defp build_creds(op) do
    base = %{
      access_key_id: op.access_key_id,
      secret_access_key: op.secret_access_key,
      region: op.region,
      service: op.service,
      token: Map.get(op, :security_token),
      now: Map.get(op, :now) || DateTime.utc_now()
    }

    case Map.get(op, :payload_hash) do
      nil -> base
      hash -> Map.put(base, :payload_hash, hash)
    end
  end

  # -- endpoint + credential resolution --------------------------------------

  defp resolve_endpoint(svc_opts, default_host_fn, region) do
    {
      strip_scheme(svc_opts[:scheme] || "https"),
      svc_opts[:host] || default_host_fn.(region),
      svc_opts[:port]
    }
  end

  defp strip_scheme(scheme) do
    scheme
    |> to_string()
    |> String.replace_suffix("://", "")
  end

  defp port_suffix(_scheme, nil), do: ""
  defp port_suffix("https", 443), do: ""
  defp port_suffix("http", 80), do: ""
  defp port_suffix(_scheme, port), do: ":#{port}"
end
