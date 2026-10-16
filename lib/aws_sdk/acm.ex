defmodule AwsSDK.ACM do
  @moduledoc """
  `AwsSDK.ACM` provides an API for AWS Certificate Manager.

  This API calls the ACM JSON 1.1 API directly over HTTP (via `AwsSDK.HTTP`),
  signs requests with SigV4 (`AwsSDK.Signer`), encodes and decodes JSON with
  Erlang's built-in `:json`, and returns `{:ok, %{body: body, headers: headers}}`
  with the body's keys converted to `snake_case` atoms.

  Credentials and region are flat top-level opts on every call, exactly as in
  the other service modules (`:access_key_id`, `:secret_access_key`,
  `:security_token`, `:region`, `:profile`).

  The following options are also available:

    - `:acm` - A keyword list of ACM request overrides. Supported keys:
      `:headers`, `:body`, `:http`, `:url`.

    - `:sandbox` - A keyword list to override sandbox configuration.
        - `:enabled` - Whether sandbox mode is enabled.

  ## Sandbox

  Add the following to your `test_helper.exs`:

      AwsSDK.ACM.Sandbox.start_link()

  and register responses:

      AwsSDK.ACM.Sandbox.set_list_certificates_responses([
        fn -> {:ok, %{body: %{certificate_summary_list: []}, headers: %{}}} end
      ])

  https://docs.aws.amazon.com/acm/latest/APIReference/Welcome.html
  """

  alias AwsSDK.Client
  alias AwsSDK.Operation
  alias ExUtils.Serializer

  @service "acm"
  @content_type "application/x-amz-json-1.1"
  @target_prefix "CertificateManager"

  @doc """
  Lists the certificates in the account and region.

  Maps to AWS `ListCertificates`.

  ## Options

    * `:certificate_statuses` - List of statuses to include, such as
      `["ISSUED"]`.
    * `:max_items` - The most results to return.
    * `:next_token` - Where to continue a truncated answer.
  """
  @spec list_certificates(opts :: keyword()) ::
          {:ok, %{body: map(), headers: map()}} | {:error, term()}
  def list_certificates(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_certificates_response(opts)
    else
      do_list_certificates(opts)
    end
  end

  defp do_list_certificates(opts) do
    data =
      %{}
      |> maybe_put("CertificateStatuses", opts[:certificate_statuses])
      |> maybe_put("MaxItems", opts[:max_items])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <- build_operation("ListCertificates", data, opts),
         {:ok, %{body: body, headers: headers}} <- Client.request(op) do
      {:ok,
       %{
         body: Serializer.deserialize(decode_body(body), deserialize_opts(opts)),
         headers: Client.deserialize_headers(headers, opts)
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Request building
  # ---------------------------------------------------------------------------

  @doc false
  def build_operation(action, data, opts) do
    with {:ok, config} <- Client.resolve_config(:acm, opts, &"acm.#{&1}.amazonaws.com") do
      op = %Operation{
        method: :post,
        url: Client.simple_url(config),
        headers: [
          {"content-type", @content_type},
          {"x-amz-target", "#{@target_prefix}.#{action}"}
        ],
        body: encode_body(data),
        service: @service,
        region: config.region,
        access_key_id: config.access_key_id,
        secret_access_key: config.secret_access_key,
        security_token: config.security_token,
        http: Keyword.get(opts, :http, [])
      }

      {:ok, apply_overrides(op, opts[:acm] || [])}
    end
  end

  defp encode_body(data) when map_size(data) === 0, do: "{}"
  defp encode_body(data), do: data |> :json.encode() |> IO.iodata_to_binary()

  defp decode_body(""), do: %{}

  defp decode_body(binary) when is_binary(binary) do
    :json.decode(binary)
  rescue
    _ -> binary
  end

  # AWS owns the response-body namespace and adds new fields over time, so
  # atom-safety is relaxed here by default, as in the other JSON services.
  # Callers can still override these options by passing their own `opts`.
  @deserialize_defaults [to_existing_atom: false, strict: false]
  defp deserialize_opts(opts), do: Keyword.merge(@deserialize_defaults, opts)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # ---------------------------------------------------------------------------
  # Sandbox delegation
  # ---------------------------------------------------------------------------

  defp sandbox?(opts) do
    sandbox_opts = opts[:sandbox] || []
    cfg = AwsSDK.Config.sandbox()
    enabled = Keyword.get(sandbox_opts, :enabled, cfg[:enabled])

    enabled and not sandbox_disabled?()
  end

  if Code.ensure_loaded?(SandboxRegistry) do
    @doc false
    defdelegate sandbox_disabled?, to: AwsSDK.ACM.Sandbox

    @doc false
    defdelegate sandbox_list_certificates_response(opts),
      to: AwsSDK.ACM.Sandbox,
      as: :list_certificates_response
  else
    defp sandbox_disabled?, do: true
    defp sandbox_list_certificates_response(_), do: raise("sandbox not available")
  end

  # ---------------------------------------------------------------------------
  # Overrides
  # ---------------------------------------------------------------------------

  @override_keys [:headers, :body, :http, :url]

  defp apply_overrides(op, overrides) do
    Enum.reduce(@override_keys, op, fn key, acc ->
      case Keyword.fetch(overrides, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end
end
