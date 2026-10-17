defmodule AwsSDK.Error do
  @moduledoc """
  The only module that builds aws_sdk errors. Every error in aws_sdk is
  `AwsSDK.Error.new(kind, details)`. The kind picks the code from the table
  below. The message is the code's standard wording, so it is the same for
  every error with that code. Everything specific to one error, including
  its kind, is in `details`.
  """

  @codes %{
    transport_error: :internal_server_error,
    invalid_json: :bad_gateway,
    unexpected_response: :bad_gateway,
    error_in_success_response: :bad_gateway,
    missing_credentials: :unauthorized,
    credential_fetch_failed: :internal_server_error,
    profile_not_found: :not_found,
    unresolvable_profile: :bad_request,
    assume_role_missing_source_profile: :bad_request,
    assume_role_self_reference: :bad_request,
    credential_process_failed: :internal_server_error,
    credential_process_invalid: :bad_gateway,
    sso_not_configured: :bad_request,
    sso_start_url_missing: :bad_request,
    sso_region_missing: :bad_request,
    sso_session_not_found: :not_found,
    sso_token_expired: :unauthorized,
    sso_oidc_error: :bad_gateway,
    sso_login_declined: :forbidden,
    sso_login_aborted: :forbidden,
    sso_failed: :unauthorized,
    file_error: :internal_server_error,
    bucket_already_exists: :conflict,
    object_already_exists: :conflict,
    multipart_upload_too_large: :forbidden,
    content_type_mismatch: :forbidden,
    task_exited: :internal_server_error,
    copy_failed: :internal_server_error,
    launch_template_version_not_deleted: :conflict,
    resource_not_found: :not_found,
    sandbox_registry_not_started: :internal_server_error
  }

  @doc """
  Builds the error for `kind`, with `details` describing this one failure.

  `:http_error` takes its code from `details.status` and AWS's own error
  code in `details.response`:

    * 3xx → `:bad_request`
    * 5xx → `:service_unavailable`
    * a code containing `NotFound`, or starting with `NoSuch` → `:not_found`
    * a code starting with `AccessDenied`, or `UnauthorizedOperation` →
      `:forbidden`
    * a code containing `Malformed` or `Validation` → `:bad_request`
    * a code containing `AlreadyExists` or `AlreadyOwnedByYou` → `:conflict`
    * any other code, or a body with none (a HEAD answer) → the status's
      own code

  ## Examples

      AwsSDK.Error.new(:http_error, %{status: 404, response: "", headers: []})
      #=> %ErrorMessage{
      #=>   code: :not_found,
      #=>   message: "not found",
      #=>   details: %{kind: :http_error, status: 404, response: "", headers: []}
      #=> }
  """
  @spec new(atom(), map()) :: ErrorMessage.t()
  def new(kind, details) do
    code = code(kind, details)

    %ErrorMessage{code: code, message: message(code), details: Map.put(details, :kind, kind)}
  end

  defp code(:http_error, details), do: http_code(details.status, aws_error_code(details.response))
  defp code(kind, _details), do: Map.fetch!(@codes, kind)

  defp message(code) do
    code
    |> Plug.Conn.Status.code()
    |> Plug.Conn.Status.reason_phrase()
    |> String.downcase()
  end

  defp http_code(status, _aws_code) when status in 300..399, do: :bad_request
  defp http_code(status, _aws_code) when status >= 500, do: :service_unavailable
  defp http_code(status, nil), do: Plug.Conn.Status.reason_atom(status)

  defp http_code(status, aws_code) do
    cond do
      not_found_code?(aws_code) -> :not_found
      forbidden_code?(aws_code) -> :forbidden
      bad_request_code?(aws_code) -> :bad_request
      conflict_code?(aws_code) -> :conflict
      true -> Plug.Conn.Status.reason_atom(status)
    end
  end

  defp aws_error_code(response) do
    case Regex.run(~r{<Code>([^<]+)</Code>|"__type":"(?:[^"#]*#)?([^"]+)"}, response,
           capture: :all_but_first
         ) do
      ["", json_code] -> json_code
      [xml_code | _] -> xml_code
      nil -> nil
    end
  end

  defp not_found_code?(aws_code) do
    String.contains?(aws_code, "NotFound") or String.starts_with?(aws_code, "NoSuch")
  end

  defp forbidden_code?(aws_code) do
    String.starts_with?(aws_code, "AccessDenied") or aws_code === "UnauthorizedOperation"
  end

  defp bad_request_code?(aws_code) do
    String.contains?(aws_code, "Malformed") or String.contains?(aws_code, "Validation")
  end

  defp conflict_code?(aws_code) do
    String.contains?(aws_code, "AlreadyExists") or String.contains?(aws_code, "AlreadyOwnedByYou")
  end
end
