defmodule AwsSDK.ServiceQuotas do
  @moduledoc """
  `AwsSDK.ServiceQuotas` provides an API for Service Quotas.

  This API calls the Service Quotas JSON 1.1 API directly over HTTP (via
  `AwsSDK.HTTP`), signs requests with SigV4 (`AwsSDK.Signer`), encodes and
  decodes JSON with Erlang's built-in `:json`, and returns
  `{:ok, %{body: body, headers: headers}}` with the body's keys converted to
  `snake_case` atoms.

  Credentials and region are flat top-level opts on every call, exactly as in
  the other service modules (`:access_key_id`, `:secret_access_key`,
  `:security_token`, `:region`, `:profile`).

  The following options are also available:

    - `:service_quotas` - A keyword list of Service Quotas request overrides.
      Supported keys: `:headers`, `:body`, `:http`, `:url`.

    - `:sandbox` - A keyword list to override sandbox configuration.
        - `:enabled` - Whether sandbox mode is enabled.

  ## Sandbox

  Add the following to your `test_helper.exs`:

      AwsSDK.ServiceQuotas.Sandbox.start_link()

  and register responses, keyed by quota code:

      AwsSDK.ServiceQuotas.Sandbox.set_get_service_quota_responses([
        {"L-1216C47A", fn -> {:ok, %{body: %{quota: %{value: 5.0}}, headers: %{}}} end}
      ])

  https://docs.aws.amazon.com/servicequotas/2019-06-24/apireference/Welcome.html
  """

  alias AwsSDK.Client
  alias AwsSDK.Operation
  alias ExUtils.Serializer

  @service "servicequotas"
  @content_type "application/x-amz-json-1.1"
  @target_prefix "ServiceQuotasV20190624"

  @doc """
  Returns the value of one quota as it applies to the account, including any
  increase already granted.

  Maps to AWS `GetServiceQuota`.

  ## Arguments

    * `service_code` - The service, such as `"ec2"`.
    * `quota_code` - The quota, such as `"L-1216C47A"` (Running On-Demand
      Standard instances, counted in vCPUs).
    * `opts` - A keyword list of options.
  """
  @spec get_service_quota(service_code :: binary(), quota_code :: binary(), opts :: keyword()) ::
          {:ok, %{body: map(), headers: map()}} | {:error, term()}
  def get_service_quota(service_code, quota_code, opts \\ []) do
    if sandbox?(opts) do
      sandbox_get_service_quota_response(service_code, quota_code, opts)
    else
      do_get_service_quota(service_code, quota_code, opts)
    end
  end

  defp do_get_service_quota(service_code, quota_code, opts) do
    data = %{"ServiceCode" => service_code, "QuotaCode" => quota_code}

    with {:ok, op} <- build_operation("GetServiceQuota", data, opts),
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
    with {:ok, config} <-
           Client.resolve_config(:service_quotas, opts, &"servicequotas.#{&1}.amazonaws.com") do
      op = %Operation{
        method: :post,
        url: Client.simple_url(config),
        headers: [
          {"content-type", @content_type},
          {"x-amz-target", "#{@target_prefix}.#{action}"}
        ],
        body: data |> :json.encode() |> IO.iodata_to_binary(),
        service: @service,
        region: config.region,
        access_key_id: config.access_key_id,
        secret_access_key: config.secret_access_key,
        security_token: config.security_token,
        http: Keyword.get(opts, :http, [])
      }

      {:ok, apply_overrides(op, opts[:service_quotas] || [])}
    end
  end

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
    defdelegate sandbox_disabled?, to: AwsSDK.ServiceQuotas.Sandbox

    @doc false
    defdelegate sandbox_get_service_quota_response(service_code, quota_code, opts),
      to: AwsSDK.ServiceQuotas.Sandbox,
      as: :get_service_quota_response
  else
    defp sandbox_disabled?, do: true
    defp sandbox_get_service_quota_response(_, _, _), do: raise("sandbox not available")
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
