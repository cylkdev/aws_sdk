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
    * `:key_types` - Key types to include, such as `["RSA_4096"]`. AWS
      returns only RSA_2048 certificates when this is not given.
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
      |> maybe_put("Includes", includes(opts[:key_types]))
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

  @doc """
  Requests a public or private certificate.

  Maps to AWS `RequestCertificate`. A public certificate stays
  `PENDING_VALIDATION` until its domains are validated.

  ## Arguments

    * `domain_name` - The fully qualified domain name to secure, such as
      `"www.example.com"` or `"*.example.com"`.
    * `opts` - Shared options.

  ## Options

    * `:validation_method` - `"DNS"` or `"EMAIL"`.
    * `:subject_alternative_names` - List of additional names to secure.
    * `:idempotency_token` - Calls with the same token within an hour
      return the same certificate.
    * `:domain_validation_options` - List of maps, such as
      `[%{"DomainName" => "www.example.com", "ValidationDomain" => "example.com"}]`.
    * `:options` - Map, such as
      `%{"CertificateTransparencyLoggingPreference" => "ENABLED"}`.
    * `:certificate_authority_arn` - A private CA, for a private certificate.
    * `:tags` - List of `%{"Key" => ..., "Value" => ...}` maps.
    * `:key_algorithm` - Such as `"RSA_2048"` or `"EC_prime256v1"`.
    * `:managed_by` - The service that manages the certificate.
    * `:raw_body` - When true, `body` is the JSON ACM answered, undecoded,
      as the evidence a parser test is written from.

  ## Examples

      AwsSDK.ACM.request_certificate("www.example.com", validation_method: "DNS")
      #=> {:ok,
      #=>  %{
      #=>    body: %{
      #=>      certificate_arn:
      #=>        "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      #=>    },
      #=>    headers: %{...}
      #=>  }}
  """
  @spec request_certificate(domain_name :: String.t(), opts :: keyword()) ::
          {:ok, %{body: map(), headers: map()}} | {:error, term()}
  def request_certificate(domain_name, opts \\ []) when is_binary(domain_name) do
    if sandbox?(opts) do
      sandbox_request_certificate_response(domain_name, opts)
    else
      do_request_certificate(domain_name, opts)
    end
  end

  defp do_request_certificate(domain_name, opts) do
    data = request_certificate_data(domain_name, opts)

    with {:ok, op} <- build_operation("RequestCertificate", data, opts),
         {:ok, %{body: body, headers: headers}} <- Client.request(op) do
      body = if opts[:raw_body], do: body, else: parse_request_certificate(body, opts)
      {:ok, %{body: body, headers: Client.deserialize_headers(headers, opts)}}
    end
  end

  defp request_certificate_data(domain_name, opts) do
    %{"DomainName" => domain_name}
    |> maybe_put("ValidationMethod", opts[:validation_method])
    |> maybe_put("SubjectAlternativeNames", opts[:subject_alternative_names])
    |> maybe_put("IdempotencyToken", opts[:idempotency_token])
    |> maybe_put("DomainValidationOptions", opts[:domain_validation_options])
    |> maybe_put("Options", opts[:options])
    |> maybe_put("CertificateAuthorityArn", opts[:certificate_authority_arn])
    |> maybe_put("Tags", opts[:tags])
    |> maybe_put("KeyAlgorithm", opts[:key_algorithm])
    |> maybe_put("ManagedBy", opts[:managed_by])
  end

  @doc false
  def request_certificate_data_for_test(domain_name, opts \\ []),
    do: request_certificate_data(domain_name, opts)

  @doc false
  def parse_request_certificate_for_test(json), do: parse_request_certificate(json, [])

  defp parse_request_certificate(body, opts) do
    body
    |> decode_body()
    |> Serializer.deserialize(deserialize_opts(opts))
  end

  @doc """
  Deletes a certificate and its private key.

  Maps to AWS `DeleteCertificate`. AWS refuses to delete a certificate
  another AWS service, such as a load balancer listener, still uses.

  ## Arguments

    * `certificate_arn` - The certificate ARN.
    * `opts` - Shared options.

  ## Options

    * `:raw_body` - When true, `body` is the body ACM answered, undecoded,
      as the evidence a parser test is written from.

  ## Examples

      AwsSDK.ACM.delete_certificate(
        "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      )
      #=> {:ok, %{body: %{}, headers: %{...}}}

  `DeleteCertificate` answers with an empty body, so `body` is an empty map.
  """
  @spec delete_certificate(certificate_arn :: String.t(), opts :: keyword()) ::
          {:ok, %{body: map(), headers: map()}} | {:error, term()}
  def delete_certificate(certificate_arn, opts \\ []) when is_binary(certificate_arn) do
    if sandbox?(opts) do
      sandbox_delete_certificate_response(certificate_arn, opts)
    else
      do_delete_certificate(certificate_arn, opts)
    end
  end

  defp do_delete_certificate(certificate_arn, opts) do
    data = %{"CertificateArn" => certificate_arn}

    with {:ok, op} <- build_operation("DeleteCertificate", data, opts),
         {:ok, %{body: body, headers: headers}} <- Client.request(op) do
      body = if opts[:raw_body], do: body, else: parse_delete_certificate(body, opts)
      {:ok, %{body: body, headers: Client.deserialize_headers(headers, opts)}}
    end
  end

  @doc false
  def parse_delete_certificate_for_test(body), do: parse_delete_certificate(body, [])

  defp parse_delete_certificate(body, opts) do
    body
    |> decode_body()
    |> Serializer.deserialize(deserialize_opts(opts))
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

  defp includes(nil), do: nil
  defp includes(key_types), do: %{"keyTypes" => key_types}

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

    @doc false
    defdelegate sandbox_request_certificate_response(domain_name, opts),
      to: AwsSDK.ACM.Sandbox,
      as: :request_certificate_response

    @doc false
    defdelegate sandbox_delete_certificate_response(certificate_arn, opts),
      to: AwsSDK.ACM.Sandbox,
      as: :delete_certificate_response
  else
    defp sandbox_disabled?, do: true
    defp sandbox_list_certificates_response(_), do: raise("sandbox not available")
    defp sandbox_request_certificate_response(_, _), do: raise("sandbox not available")
    defp sandbox_delete_certificate_response(_, _), do: raise("sandbox not available")
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
