defmodule AwsSDK.Operation do
  @moduledoc """
  Pure-data request descriptor for a single AWS API call.

  One struct serves every service. A facade builds a populated
  `AwsSDK.Operation` and hands it to `AwsSDK.Client.request/1`: the body is
  already encoded, the headers are already populated, the URL is already
  composed.

  `:payload_hash`, `:stream_upload` and `:stream_response` are only used
  by S3; their defaults are inert for every other service.
  """

  @enforce_keys [
    :method,
    :url,
    :headers,
    :body,
    :service,
    :region,
    :access_key_id,
    :secret_access_key
  ]
  defstruct [
    :method,
    :url,
    :headers,
    :body,
    :service,
    :region,
    :access_key_id,
    :secret_access_key,
    :security_token,
    :payload_hash,
    http: [],
    stream_upload: false,
    stream_response: false
  ]

  @type method :: :get | :put | :post | :delete | :head

  @type t :: %__MODULE__{
          method: method,
          url: String.t(),
          headers: [{String.t(), String.t()}],
          body: iodata | Enumerable.t(),
          service: String.t(),
          region: String.t(),
          access_key_id: String.t(),
          secret_access_key: String.t(),
          security_token: String.t() | nil,
          payload_hash: String.t() | nil,
          http: keyword,
          stream_upload: boolean,
          stream_response: boolean
        }
end
