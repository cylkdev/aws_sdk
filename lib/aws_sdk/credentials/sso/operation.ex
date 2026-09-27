defmodule AwsSDK.Credentials.SSO.Operation do
  @moduledoc """
  Pure-data request descriptor for an Identity Center SSO /
  OIDC HTTP call.

  Unlike the SigV4 Operation structs in this library, SSO
  operations are not signed — the portal endpoint uses a bearer
  token (`x-amz-sso_bearer_token`) and the OIDC endpoints are
  unauthenticated POSTs that carry `clientId` and `clientSecret`
  in the body. Built by the SSO provider, refresher, and device-code
  login flow, and handed to `AwsSDK.Credentials.SSO.execute/1`.
  """

  @enforce_keys [:method, :url, :headers, :body]
  defstruct [:method, :url, :headers, :body, http: []]

  @type t :: %__MODULE__{
          method: :get | :post,
          url: String.t(),
          headers: [{String.t(), String.t()}],
          body: iodata,
          http: keyword
        }
end
