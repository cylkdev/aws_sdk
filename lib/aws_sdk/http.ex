defmodule AwsSDK.HTTP do
  @moduledoc """
  `Req`-based HTTP primitive for direct AWS API calls.

  All requests run through a single supervised `Finch` instance
  (`AwsSDK.HTTP.FinchPool`), which holds a dedicated pool per well-known AWS
  service endpoint plus a `:default` pool for S3 virtual-hosted bucket
  origins. Control-plane services use HTTP/2 multiplexing; S3 stays on
  HTTP/1.1. See `AwsSDK.HTTP.FinchPool` for tuning.

  Req's defaults (retries, redirect following, body decoding,
  request/response compression) are all **disabled** here because:

    * AWS clients sign a specific set of headers and bytes; Req
      retrying, following a redirect, or rewriting the body would
      invalidate the SigV4 signature produced upstream.
    * AWS services return raw JSON/XML/binary that the caller parses
      itself, so Req's content-type decoding would surprise callers.

  Three entry points:

    * `request/5` (plus `post/4` and `get/3`) — buffered bodies both
      directions. Appropriate for everything that fits in memory:
      JSON/Query API calls, list operations, header-only operations.

    * `stream_upload/5` — body is an `Enumerable` of iodata chunks
      (S3 large PUTs, multipart `upload_part`). Response is buffered.

    * `stream_download/3` — body is read lazily via a returned
      `Stream`. Used for large S3 downloads. The stream must be
      consumed in the calling process because Finch routes response
      messages to that process.
  """

  require Logger

  alias AwsSDK.HTTP.FinchPool

  @default_request_timeout 30_000

  @type method :: :get | :post | :put | :delete | :head | :patch | :options
  @type header :: {String.t(), String.t()}
  @type response :: %{status_code: non_neg_integer(), headers: [header], body: binary}
  @type stream_response :: %{
          status_code: non_neg_integer(),
          headers: [header],
          body_stream: Enumerable.t()
        }

  def start_link(opts \\ []) do
    FinchPool.start_link(opts)
  end

  def child_spec(opts \\ []) do
    FinchPool.child_spec(opts)
  end

  @doc """
  Issues a buffered HTTP request.

  ## Options

    * `:request_timeout` — milliseconds for the whole response, default `#{@default_request_timeout}`.
      Forwarded to Finch as `:receive_timeout`.
    * `:connect_timeout` — accepted for API compatibility and ignored here;
      connect timeouts live on the Finch pool configured in `AwsSDK.HTTP.FinchPool`.

  ## Examples

      AwsSDK.HTTP.request(:get, "https://example.com/health", "", [{"accept", "text/plain"}])
      #=> {:ok, %{status: 200, body: "ok", headers: [{"content-type", "text/plain"}]}}

      AwsSDK.HTTP.request(:get, "https://example.com/missing", "", [])
      #=> {:ok, %{status: 404, body: "not found", headers: [...]}}

      AwsSDK.HTTP.request(:get, "https://unreachable.invalid", "", [], receive_timeout: 1_000)
      #=> {:error, %Mint.TransportError{reason: :nxdomain}}

  A non-2xx response is still `{:ok, _}` -- status branching happens in
  `AwsSDK.Client`, not here. Only transport failures return `{:error, _}`.
  """
  @spec request(method, String.t(), iodata, [header], keyword) ::
          {:ok, response} | {:error, %{reason: term}}
  def request(method, url, body, headers, opts \\ []) when is_atom(method) do
    :ok = validate_url!(url)

    [method: method, url: url, headers: headers]
    |> put_body(body)
    |> Keyword.merge(base_opts(opts))
    |> Req.request()
    |> handle_response()
  end

  # Req >= 0.7 infers the verb from the presence of a body, and an empty
  # binary counts as present -- so `body: ""` on a GET was silently rewritten
  # into a POST. Against the Identity Center portal that surfaced as
  # com.amazonaws.switchboard.portal#MethodNotAllowedException (405). Omit the
  # key when there is nothing to send, leaving `:method` as the only thing
  # that decides the verb.
  defp put_body(req_opts, body) when body in [nil, "", []], do: req_opts
  defp put_body(req_opts, body), do: Keyword.put(req_opts, :body, body)

  @doc """
  Convenience wrapper for `request(:post, url, body, headers, opts)`.

  ## Examples

      AwsSDK.HTTP.post("https://example.com/api", ~s({"a":1}), [{"content-type", "application/json"}])
      #=> {:ok, %{status: 200, body: ~s({"ok":true}), headers: [...]}}
  """
  @spec post(String.t(), iodata, [header], keyword) :: {:ok, response} | {:error, %{reason: term}}
  def post(url, body, headers, opts \\ []) do
    request(:post, url, body, headers, opts)
  end

  @doc """
  Convenience wrapper for `request(:get, url, nil, headers, opts)`.

  ## Examples

      AwsSDK.HTTP.get("https://example.com/health")
      #=> {:ok, %{status: 200, body: "ok", headers: [...]}}

      # Used for IMDS credential lookups, which need a token header.
      AwsSDK.HTTP.get("http://169.254.169.254/latest/meta-data/iam/security-credentials/",
        [{"x-aws-ec2-metadata-token", token}]
      )
      #=> {:ok, %{status: 200, body: "my-instance-role", headers: [...]}}
  """
  @spec get(String.t(), [header], keyword) :: {:ok, response} | {:error, %{reason: term}}
  def get(url, headers \\ [], opts \\ []) do
    request(:get, url, nil, headers, opts)
  end

  @doc """
  Sends a request whose body is produced by an `Enumerable` of iodata
  chunks. Response body is buffered.

  The caller should set `content-length` on the request headers — S3
  requires it for SigV4 unsigned-payload streaming. `content-type` and
  other S3 headers should be included in `headers` so they are part of
  the signature computed upstream.

  ## Examples

      body = File.stream!("/tmp/big.bin", [], 5_242_880)

      AwsSDK.HTTP.stream_upload(
        :put,
        "https://uploads.s3.us-east-1.amazonaws.com/big.bin",
        body,
        [{"content-length", "12000000"}]
      )
      #=> {:ok, %{status: 200, body: "", headers: [{"etag", "\"9a03\""}]}}

  The stream is sent chunk by chunk, so the file is never held in memory in
  full. S3 needs an accurate `content-length`, since it does not accept
  chunked transfer encoding for this.
  """
  @spec stream_upload(method, String.t(), Enumerable.t(), [header], keyword) ::
          {:ok, response} | {:error, %{reason: term}}
  def stream_upload(method, url, body_stream, headers, opts \\ []) when is_atom(method) do
    :ok = validate_url!(url)

    [method: method, url: url, headers: headers]
    |> put_body(body_stream)
    |> Keyword.merge(base_opts(opts))
    |> Req.request()
    |> handle_response()
  end

  @doc """
  Issues a GET request and returns a `Stream` over the response body
  chunks. The stream must be consumed in the calling process because
  Finch routes response messages to that process.

  ## Examples

      AwsSDK.HTTP.stream_download("https://uploads.s3.us-east-1.amazonaws.com/big.bin")
      #=> {:ok, %{status: 200, headers: [...], stream: #Function<...>}}

      # Write to disk without buffering the object in memory.
      {:ok, %{stream: chunks}} = AwsSDK.HTTP.stream_download(url)
      Stream.into(chunks, File.stream!("/tmp/big.bin")) |> Stream.run()

  Backs `AwsSDK.S3.get_object/3` when `:stream_to` is given.
  """
  @spec stream_download(String.t(), [header], keyword) ::
          {:ok, stream_response} | {:error, %{reason: term}}
  def stream_download(url, headers \\ [], opts \\ []) do
    :ok = validate_url!(url)
    timeout = request_timeout(opts)

    result =
      [method: :get, url: url, headers: headers, into: :self]
      |> Keyword.merge(base_opts(opts))
      |> Req.request()

    case result do
      {:ok, %Req.Response{status: status, headers: resp_headers} = response} ->
        {:ok,
         %{
           status_code: status,
           headers: to_list_headers(resp_headers),
           body_stream: body_stream(response, timeout)
         }}

      {:error, error} ->
        {:error, %{reason: error_reason(error)}}
    end
  end

  defp base_opts(opts) do
    [
      # Req 0.7 wants the pool under `finch: [name: ...]`; a bare atom is
      # deprecated and warns on every request.
      finch: [name: FinchPool.name()],
      receive_timeout: request_timeout(opts),
      retry: false,
      redirect: false,
      decode_body: false,
      compressed: false
    ]
  end

  defp handle_response({:ok, %Req.Response{status: status, headers: headers, body: body}}) do
    {:ok,
     %{
       status_code: status,
       headers: to_list_headers(headers),
       body: to_binary(body)
     }}
  end

  defp handle_response({:error, error}), do: {:error, %{reason: error_reason(error)}}

  defp body_stream(%Req.Response{body: %Req.Response.Async{}} = response, timeout) do
    Stream.resource(
      fn -> {response, []} end,
      fn state -> step(state, timeout) end,
      fn {response, _pending} -> cancel_stream(response) end
    )
  end

  # Runs in `Stream.resource/3`'s after-fun, which must return the accumulator
  # and cannot report failure. `cancel_fun` is supplied by the adapter, so its
  # return is not a fixed shape; match both outcomes rather than discard it.
  defp cancel_stream(response) do
    case Req.cancel_async_response(response) do
      :ok ->
        :ok

      other ->
        Logger.warning("[AwsSDK.HTTP] cancelling the response stream returned #{inspect(other)}")
        :ok
    end
  end

  defp step({response, []}, timeout) do
    receive do
      msg ->
        case Req.parse_message(response, msg) do
          {:ok, events} -> step({response, events}, timeout)
          {:error, _exception} -> {:halt, {response, []}}
          :unknown -> {[], {response, []}}
        end
    after
      timeout -> {:halt, {response, []}}
    end
  end

  defp step({response, [:done | _]}, _timeout), do: {:halt, {response, []}}
  defp step({response, [{:data, chunk} | rest]}, _timeout), do: {[chunk], {response, rest}}
  defp step({response, [_other | rest]}, timeout), do: step({response, rest}, timeout)

  defp to_list_headers(headers) when is_map(headers) do
    for {k, vs} <- headers, v <- List.wrap(vs), do: {to_string(k), to_string(v)}
  end

  defp to_binary(body) when is_binary(body), do: body
  defp to_binary(nil), do: ""
  defp to_binary(body) when is_list(body), do: IO.iodata_to_binary(body)

  defp request_timeout(opts) do
    Keyword.get(opts, :request_timeout, @default_request_timeout)
  end

  defp error_reason(%{reason: reason}), do: reason
  defp error_reason(other), do: other

  defp validate_url!(url) do
    uri = URI.parse(url)
    :ok = validate_host!(uri)
    :ok = validate_scheme!(uri)
  end

  defp validate_host!(uri) do
    case uri do
      %URI{host: host} when is_binary(host) and host !== "" -> :ok
      %URI{} -> raise ArgumentError, "missing host in url: #{inspect(uri)}"
    end
  end

  defp validate_scheme!(uri) do
    case uri do
      %URI{scheme: "https"} -> :ok
      %URI{scheme: "http"} -> :ok
      %URI{scheme: scheme} -> raise ArgumentError, "unsupported scheme: #{inspect(scheme)}"
    end
  end
end
