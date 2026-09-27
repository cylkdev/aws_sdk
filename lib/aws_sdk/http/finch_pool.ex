defmodule AwsSDK.HTTP.FinchPool do
  @moduledoc """
  Supervised `Finch` instance that backs `AwsSDK.HTTP` (via `Req`).

  The full pool map used by default is the `@default_pools` module
  attribute below. It holds a dedicated pool per well-known AWS service
  endpoint in `us-east-1`, plus a `:default` pool that catches S3
  virtual-hosted bucket origins and any origin not enumerated
  (LocalStack, custom endpoints, cross-region calls).

  ## Overriding

  There is no merging. If you supply a `:pools` map we pass it to Finch
  verbatim; otherwise we use `@default_pools` verbatim. Two override
  paths:

    * Pass `pools: %{...}` when you start `AwsSDK.HTTP.FinchPool` yourself.
    * Set `config :aws_sdk, http_pools: %{...}` in the application env.

  Callers running in a region other than `us-east-1` must override —
  the default map is `us-east-1`-only.

  ## TLS

  The enumerated HTTPS pools are pinned to TLS 1.3 with session-ticket
  resumption and the OTP built-in CA bundle. The `:default` pool is
  scheme-agnostic (it may serve plaintext HTTP origins such as
  LocalStack), so it only carries a connect `timeout`. S3 bucket
  origins routed to `:default` still negotiate TLS 1.3 via OTP SSL
  defaults; the explicit version pin and ticket reuse only apply to
  the enumerated HTTPS pools.
  """

  @name __MODULE__

  @connect_timeout 5_000
  @tls_transport_opts [
    versions: [:"tlsv1.3"],
    cacerts: :public_key.cacerts_get(),
    session_tickets: :auto,
    timeout: @connect_timeout
  ]
  @plain_transport_opts [timeout: @connect_timeout]

  @doc """
  Registered name of the Finch instance used by `AwsSDK.HTTP`.

  ## Examples

      AwsSDK.HTTP.FinchPool.name()
      #=> AwsSDK.HTTP.FinchPool

  Pass it to Finch directly when you need a call this library does not
  wrap: `Finch.build(:get, url) |> Finch.request(AwsSDK.HTTP.FinchPool.name())`.
  """
  @spec name() :: atom()
  def name, do: @name

  def start_link(opts) do
    opts
    |> Keyword.put(:name, @name)
    |> Keyword.put_new(:pools, default_pools(opts))
    |> Finch.start_link()
  end

  @doc false
  def child_spec(opts) do
    %{
      id: @name,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  defp default_pools(opts) do
    region = opts[:region] || "us-east-1"

    %{
      "https://s3.#{region}.amazonaws.com" => [
        protocols: [:http1],
        size: 50,
        count: 1,
        conn_max_idle_time: 60_000,
        pool_max_idle_time: 300_000,
        conn_opts: [transport_opts: @tls_transport_opts]
      ],
      "https://events.#{region}.amazonaws.com" => [
        protocols: [:http2, :http1],
        size: 25,
        count: 1,
        conn_max_idle_time: 60_000,
        pool_max_idle_time: 300_000,
        conn_opts: [transport_opts: @tls_transport_opts]
      ],
      "https://logs.#{region}.amazonaws.com" => [
        protocols: [:http2, :http1],
        size: 50,
        count: 1,
        conn_max_idle_time: 60_000,
        pool_max_idle_time: 300_000,
        conn_opts: [transport_opts: @tls_transport_opts]
      ],
      "https://iam.#{region}.amazonaws.com" => [
        protocols: [:http2, :http1],
        size: 10,
        count: 1,
        conn_max_idle_time: 60_000,
        pool_max_idle_time: 300_000,
        conn_opts: [transport_opts: @tls_transport_opts]
      ],
      "https://sso.#{region}.amazonaws.com" => [
        protocols: [:http2, :http1],
        size: 10,
        count: 1,
        conn_max_idle_time: 60_000,
        pool_max_idle_time: 300_000,
        conn_opts: [transport_opts: @tls_transport_opts]
      ],
      "https://identitystore.#{region}.amazonaws.com" => [
        protocols: [:http2, :http1],
        size: 10,
        count: 1,
        conn_max_idle_time: 60_000,
        pool_max_idle_time: 300_000,
        conn_opts: [transport_opts: @tls_transport_opts]
      ],
      "https://organizations.#{region}.amazonaws.com" => [
        protocols: [:http2, :http1],
        size: 10,
        count: 1,
        conn_max_idle_time: 60_000,
        pool_max_idle_time: 300_000,
        conn_opts: [transport_opts: @tls_transport_opts]
      ],
      "https://sts.#{region}.amazonaws.com" => [
        protocols: [:http2, :http1],
        size: 10,
        count: 1,
        conn_max_idle_time: 60_000,
        pool_max_idle_time: 300_000,
        conn_opts: [transport_opts: @tls_transport_opts]
      ],
      default: [
        protocols: [:http1],
        size: 100,
        count: 1,
        conn_max_idle_time: 60_000,
        pool_max_idle_time: 120_000,
        conn_opts: [transport_opts: @plain_transport_opts]
      ]
    }
  end
end
