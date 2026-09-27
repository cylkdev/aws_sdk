defmodule AwsSDK.STS do
  @moduledoc """
  `AwsSDK.STS` provides an API for AWS Security Token Service (STS).

  This module calls the AWS STS Query API directly via `AwsSDK.HTTP` and
  `AwsSDK.Signer` (through `AwsSDK.Client`).

  STS's public API is XML-only at the AWS wire level. The service model
  (`botocore/data/sts/2011-06-15/service-2.json`) declares
  `metadata.protocols = ["query"]`, and AWS does not expose a JSON STS
  endpoint. The form-urlencoded request / XML response handling here
  (XPath extraction via `SweetXml`) is a consequence of AWS's protocol
  choice, not a library decision.

  STS exposes both a legacy global endpoint (`sts.amazonaws.com`) and
  regional endpoints at `sts.{region}.amazonaws.com`. This facade uses
  the regional form (mirroring the AWS CLI's default behavior), signed
  under the configured `:region` (default `us-east-1`).

  ## Shared Options

  Credentials and region are flat top-level opts on every call (ex_aws shape).
  Each accepts a literal, a source tuple, or a list of sources (first
  non-nil wins):

    - `:access_key_id`, `:secret_access_key`, `:security_token`, `:region` -
      Sources: literal binary, `{:system, "ENV"}`, `:instance_role`,
      `:ecs_task_role`, `{:awscli, profile}` / `{:awscli, profile, ttl}`,
      a module, or a list of any of these. Map-returning sources merge
      into the outer config. `{:awscli, _}` is not in the default chain -
      callers opt in explicitly.

  The following options are also available:

    - `:sts` - A keyword list of STS endpoint overrides. Supported keys:
      `:scheme`, `:host`, `:port`. Credentials are not read from this
      sub-list; use the top-level keys above.

    - `:sandbox` - A keyword list to override sandbox configuration.
        - `:enabled` - Whether sandbox mode is enabled.

  ## Sandbox

  Set `sandbox: [enabled: true]` to activate sandbox mode.

  ### Setup

  Add the following to your `test_helper.exs`:

      AwsSDK.STS.Sandbox.start_link()

  ### Usage

      setup do
        AwsSDK.STS.Sandbox.set_get_caller_identity_responses([
          fn -> {:ok, %{account: "123456789012", arn: "arn:aws:iam::123456789012:user/alice", user_id: "AIDA123"}} end
        ])
      end

      test "returns caller identity" do
        assert {:ok, %{account: "123456789012"}} =
                 AwsSDK.STS.get_caller_identity(sandbox: [enabled: true])
      end
  """

  import SweetXml, only: [xpath: 3, sigil_x: 2]

  alias AwsSDK.Client
  alias AwsSDK.Operation

  @service "sts"
  @content_type "application/x-www-form-urlencoded"
  @api_version "2011-06-15"
  @default_region "us-east-1"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Returns details about the IAM user or role whose credentials are used
  to call the operation.

  Wraps the STS `GetCallerIdentity` action. No request parameters are
  required - the response is derived from the signing credentials.

  Returns `{:ok, %{account: String.t(), arn: String.t(), user_id: String.t()}}`
  on success.

  ## Examples

      AwsSDK.STS.get_caller_identity()
      #=> {:ok,
      #=>  %{
      #=>    account: "123456789012",
      #=>    arn: "arn:aws:sts::123456789012:assumed-role/deploy/session",
      #=>    user_id: "AROA1EXAMPLE:session"
      #=>  }}
  """
  @spec get_caller_identity(opts :: keyword()) ::
          {:ok, %{account: String.t(), arn: String.t(), user_id: String.t()}}
          | {:error, term()}
  def get_caller_identity(opts \\ []) do
    if sandbox?(opts) do
      sandbox_get_caller_identity_response(opts)
    else
      do_get_caller_identity(opts)
    end
  end

  defp do_get_caller_identity(opts) do
    with {:ok, op} <- build_operation("GetCallerIdentity", %{}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      fields =
        xpath(body, ~x"//GetCallerIdentityResult"e,
          account: ~x"./Account/text()"s,
          arn: ~x"./Arn/text()"s,
          user_id: ~x"./UserId/text()"s
        )

      {:ok, fields}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: AssumeRole helper for credential resolution
  # ---------------------------------------------------------------------------

  @doc false
  @spec assume_role(map, map, String.t(), keyword) ::
          {:ok,
           %{
             credentials: %{
               access_key_id: String.t(),
               secret_access_key: String.t(),
               session_token: String.t(),
               expiration: DateTime.t() | nil
             },
             assumed_role_user: %{arn: String.t(), assumed_role_id: String.t()} | nil,
             packed_policy_size: integer() | nil,
             source_identity: String.t()
           }}
          | {:error, term}
  def assume_role(params, source_creds, region, opts) do
    op = %Operation{
      method: :post,
      url: opts[:endpoint] || default_url(region),
      headers: [{"content-type", @content_type}],
      body: assume_role_body(params),
      service: @service,
      region: region,
      access_key_id: source_creds.access_key_id,
      secret_access_key: source_creds.secret_access_key,
      security_token: Map.get(source_creds, :security_token),
      http: Keyword.get(opts, :http, [])
    }

    case Client.execute(op) do
      {:ok, %{body: xml}} -> parse_assume_role(xml)
      {:error, {:http_error, status, xml}} -> {:error, {:sts_http_error, status, xml}}
      {:error, reason} -> {:error, {:sts_transport_error, reason}}
    end
  end

  defp assume_role_body(params) do
    base = [
      {"Action", "AssumeRole"},
      {"Version", @api_version},
      {"RoleArn", params.role_arn},
      {"RoleSessionName", params.role_session_name},
      {"DurationSeconds", Integer.to_string(params[:duration_seconds] || 3_600)}
    ]

    base
    |> maybe_add("ExternalId", params[:external_id])
    |> maybe_add("SerialNumber", params[:serial_number])
    |> maybe_add("TokenCode", params[:token_code])
    |> URI.encode_query()
  end

  @doc false
  def parse_assume_role_for_test(xml), do: parse_assume_role(xml)

  defp parse_assume_role(xml) do
    parsed =
      xpath(
        xml,
        ~x"//AssumeRoleResponse/AssumeRoleResult"e,
        credentials: [
          ~x"./Credentials"o,
          access_key_id: ~x"./AccessKeyId/text()"s,
          secret_access_key: ~x"./SecretAccessKey/text()"s,
          session_token: ~x"./SessionToken/text()"s,
          expiration: ~x"./Expiration/text()"s
        ],
        assumed_role_user: [
          ~x"./AssumedRoleUser"o,
          arn: ~x"./Arn/text()"os,
          assumed_role_id: ~x"./AssumedRoleId/text()"os
        ],
        # Only meaningful when a policy or tags were passed, so not guaranteed.
        packed_policy_size: ~x"./PackedPolicySize/text()"oi,
        source_identity: ~x"./SourceIdentity/text()"os
      )

    case parsed do
      %{credentials: %{access_key_id: ak, secret_access_key: sk} = creds}
      when ak !== "" and sk !== "" ->
        {:ok,
         %{
           parsed
           | credentials: %{
               creds
               | # The sample response wraps the token across lines.
                 session_token: String.trim(creds.session_token),
                 expiration: parse_expiration(creds.expiration)
             }
         }}

      _ ->
        {:error, {:sts_invalid_response, xml}}
    end
  rescue
    err -> {:error, {:sts_invalid_response, Exception.message(err)}}
  end

  # An absent Expiration is legitimate; an unparseable one is not. Returning
  # nil for the latter would mean "never expires", and `AwsSDK.AuthCache` caches
  # an entry with no expiry forever -- the credentials would die at AWS while
  # this process kept reusing them. Raise instead; the caller's rescue turns
  # it into `{:error, {:sts_invalid_response, _}}`.
  defp parse_expiration(""), do: nil

  defp parse_expiration(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> dt
      {:error, reason} -> raise ArgumentError, "unparseable Expiration #{inspect(iso)}: #{reason}"
    end
  end

  defp default_url(region), do: "https://sts.#{region}.amazonaws.com/"

  defp maybe_add(list, _key, nil), do: list
  defp maybe_add(list, key, value), do: list ++ [{key, value}]

  # ---------------------------------------------------------------------------
  # Sandbox delegation
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Private helpers (Query-protocol perform/build/deserialize)
  # ---------------------------------------------------------------------------

  @doc false
  def build_operation(action, params, opts) do
    opts = Keyword.put_new(opts, :region, @default_region)

    with {:ok, config} <- Client.resolve_config(:sts, opts, &default_host/1) do
      op = %Operation{
        method: :post,
        url: Client.simple_url(config),
        headers: [{"content-type", @content_type}],
        body: encode_body(action, params),
        service: @service,
        region: config.region,
        access_key_id: config.access_key_id,
        secret_access_key: config.secret_access_key,
        security_token: config.security_token,
        http: Keyword.get(opts, :http, [])
      }

      {:ok, apply_overrides(op, opts[:sts] || [])}
    end
  end

  defp encode_body(action, params) do
    params
    |> Map.merge(%{"Action" => action, "Version" => @api_version})
    |> URI.encode_query()
  end

  defp default_host(region), do: "sts.#{region}.amazonaws.com"

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
    defdelegate sandbox_disabled?, to: AwsSDK.STS.Sandbox

    @doc false
    defdelegate sandbox_get_caller_identity_response(opts),
      to: AwsSDK.STS.Sandbox,
      as: :get_caller_identity_response
  else
    defp sandbox_disabled?, do: true

    defp sandbox_get_caller_identity_response(_), do: raise("sandbox not available")
  end

  # ---------------------------------------------------------------------------
  # Overrides / response handling
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
