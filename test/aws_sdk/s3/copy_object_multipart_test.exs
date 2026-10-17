defmodule AwsSDK.S3.CopyObjectMultipartTest do
  use ExUnit.Case, async: true

  alias AwsSDK.S3
  alias AwsSDK.S3.Sandbox

  @opts [sandbox: [enabled: true]]

  @head %{content_length: "10", x_amz_request_id: "head-req"}
  @create %{
    body: %{bucket: "dest", key: "k", upload_id: "u-1"},
    headers: %{x_amz_request_id: "c"}
  }
  @parts [{%{body: %{etag: "\"e1\""}, headers: %{x_amz_request_id: "p1"}}, 1}]

  setup do
    Sandbox.set_head_object_responses([{"src", fn -> {:ok, @head} end}])
    Sandbox.set_create_multipart_upload_responses([{"dest", fn -> {:ok, @create} end}])
    :ok
  end

  test "reports every call it made under its own key" do
    complete = %{
      complete_multipart_upload: %{body: %{etag: "\"e-1\""}, headers: %{x_amz_version_id: "v"}}
    }

    Sandbox.set_copy_parts_responses([{"dest", fn -> {:ok, @parts} end}])
    Sandbox.set_complete_multipart_upload_responses([{"dest", fn -> {:ok, complete} end}])

    assert {:ok,
            %{
              head_object: @head,
              create_multipart_upload: @create,
              copy_parts: @parts,
              complete_multipart_upload: ^complete
            }} = S3.copy_object_multipart("dest", "k", "src", "src-k", @opts)
  end

  test "a failed copy keeps prior call results and reports the abort" do
    copy_error = {:error, AwsSDK.Error.new(:copy_failed, %{copied: [], failed: [:boom]})}
    abort = %{x_amz_request_id: "abort-req"}

    Sandbox.set_copy_parts_responses([{"dest", fn -> copy_error end}])
    Sandbox.set_abort_multipart_upload_responses([{"dest", fn -> {:ok, abort} end}])

    assert {:error,
            %ErrorMessage{
              code: :internal_server_error,
              message: "internal server error",
              details: %{
                kind: :copy_failed,
                head_object: @head,
                create_multipart_upload: @create,
                copy_parts: copy_error,
                abort_multipart_upload: {:ok, abort}
              }
            }} === S3.copy_object_multipart("dest", "k", "src", "src-k", @opts)
  end
end
