defmodule AwsSDK.Credentials.SSO do
  @moduledoc """
  Convenience entry point for SSO login and HTTP dispatcher for
  Identity Center SSO and OIDC operations.

  `login/2` delegates to `AwsSDK.Credentials.SSO.Login.run/2` for the
  full device-code flow.

  `execute/1` is the dispatcher for
  `AwsSDK.Credentials.SSO.Operation` structs. Unlike
  `AwsSDK.Client.execute/1`, it does not SigV4-sign the request — the
  portal endpoint uses a bearer token (`x-amz-sso_bearer_token`) and
  the OIDC endpoints are unauthenticated POSTs. Callers interpret
  status codes themselves (since OIDC `invalid_grant`,
  `authorization_pending`, portal `401`, etc. all have distinct
  per-endpoint semantics).
  """

  alias AwsSDK.Credentials.SSO.Operation
  alias AwsSDK.HTTP

  @type response :: %{status_code: non_neg_integer, headers: list, body: binary}

  defdelegate login(profile_name, opts \\ []), to: AwsSDK.Credentials.SSO.Login, as: :run

  @spec execute(Operation.t()) ::
          {:ok, response} | {:error, {:sso_transport_error, term}}
  def execute(%Operation{} = op) do
    case dispatch(op) do
      {:ok, _} = ok -> ok
      {:error, %{reason: reason}} -> {:error, {:sso_transport_error, reason}}
    end
  end

  defp dispatch(%Operation{method: :get} = op) do
    HTTP.get(op.url, op.headers, op.http)
  end

  defp dispatch(%Operation{method: :post} = op) do
    HTTP.post(op.url, op.body, op.headers, op.http)
  end
end
