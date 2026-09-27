defmodule AwsSDK.S3.SandboxTest do
  use ExUnit.Case, async: true

  alias AwsSDK.S3
  alias AwsSDK.S3.Sandbox

  describe "list_buckets/1" do
    test "returns mocked bucket list" do
      Sandbox.set_list_buckets_responses([
        fn ->
          {:ok,
           [
             %{
               name: "test-bucket",
               creation_date: ~U[2025-09-30 20:48:01.000Z]
             }
           ]}
        end
      ])

      assert {:ok,
              [
                %{
                  name: "test-bucket",
                  creation_date: ~U[2025-09-30 20:48:01.000Z]
                }
              ]} = S3.list_buckets(sandbox: [enabled: true])
    end
  end

  describe "create_bucket/2" do
    test "returns mocked creation response" do
      Sandbox.set_create_bucket_responses([
        {"test-bucket",
         fn ->
           {:ok, %{location: "/test-bucket", x_amz_request_id: "req-123"}}
         end}
      ])

      assert {:ok, %{location: "/test-bucket", x_amz_request_id: "req-123"}} =
               S3.create_bucket("test-bucket", sandbox: [enabled: true])
    end
  end

  describe "put_object/4" do
    test "returns mocked headers" do
      Sandbox.set_put_object_responses([
        {"test-bucket",
         fn ->
           {:ok,
            %{
              etag: "9725d5a30c6130db8e169c4d9560ded7",
              date: "Fri, 19 Sep 2025 18:40:13 GMT"
            }}
         end}
      ])

      assert {:ok,
              %{
                etag: "9725d5a30c6130db8e169c4d9560ded7",
                date: "Fri, 19 Sep 2025 18:40:13 GMT"
              }} =
               S3.put_object("test-bucket", "test-object", "test-content",
                 sandbox: [enabled: true]
               )
    end

    test "supports regex bucket matching" do
      Sandbox.set_put_object_responses([
        {~r|.*|,
         fn ->
           {:ok, %{etag: "abc123"}}
         end}
      ])

      assert {:ok, %{etag: "abc123"}} =
               S3.put_object("any-bucket", "test-object", "content", sandbox: [enabled: true])
    end
  end

  describe "head_object/3" do
    test "returns mocked object metadata" do
      Sandbox.set_head_object_responses([
        {"test-bucket",
         fn ->
           {:ok,
            %{
              content_length: 123,
              content_type: "image/png",
              etag: "abcdef1234567890"
            }}
         end}
      ])

      assert {:ok,
              %{
                content_length: 123,
                content_type: "image/png",
                etag: "abcdef1234567890"
              }} = S3.head_object("test-bucket", "test-object", sandbox: [enabled: true])
    end

    test "returns error when object does not exist" do
      Sandbox.set_head_object_responses([
        {"test-bucket",
         fn ->
           {:error,
            %ErrorMessage{
              code: :not_found,
              message: "object not found",
              details: %{bucket: "test-bucket", key: "nonexistent.txt"}
            }}
         end}
      ])

      assert {:error,
              %ErrorMessage{
                code: :not_found,
                message: "object not found"
              }} = S3.head_object("test-bucket", "nonexistent.txt", sandbox: [enabled: true])
    end
  end

  describe "delete_object/3" do
    test "returns mocked response" do
      Sandbox.set_delete_object_responses([
        {"test-bucket",
         fn ->
           {:ok, ""}
         end}
      ])

      assert {:ok, ""} = S3.delete_object("test-bucket", "test-object", sandbox: [enabled: true])
    end
  end

  describe "get_object/3" do
    test "returns mocked object body" do
      Sandbox.set_get_object_responses([
        {"test-bucket", fn -> {:ok, "content for test-object"} end}
      ])

      assert {:ok, "content for test-object"} =
               S3.get_object("test-bucket", "test-object", sandbox: [enabled: true])
    end
  end

  describe "list_objects/2" do
    test "returns mocked object list" do
      Sandbox.set_list_objects_responses([
        {"test-bucket",
         fn ->
           {:ok,
            [
              %{
                key: "hello_world.txt",
                size: 12,
                storage_class: "STANDARD",
                etag: "86fb269d190d2c85f6e0468ceca42a20"
              }
            ]}
         end}
      ])

      assert {:ok,
              [
                %{
                  key: "hello_world.txt",
                  size: 12,
                  storage_class: "STANDARD"
                }
              ]} = S3.list_objects("test-bucket", sandbox: [enabled: true])
    end
  end

  describe "copy_object/5" do
    test "returns mocked copy response" do
      Sandbox.set_copy_object_responses([
        {"test-bucket",
         fn ->
           {:ok,
            %{
              last_modified: ~U[2025-08-30 01:00:00.000000Z],
              etag: "etag"
            }}
         end}
      ])

      assert {:ok,
              %{
                last_modified: ~U[2025-08-30 01:00:00.000000Z],
                etag: "etag"
              }} =
               S3.copy_object("test-bucket", "test-object", "test-bucket", "test-object",
                 sandbox: [enabled: true]
               )
    end

    test "returns error when object does not exist" do
      Sandbox.set_copy_object_responses([
        {"test-bucket",
         fn ->
           {:error,
            %ErrorMessage{
              code: :not_found,
              message: "object not found"
            }}
         end}
      ])

      assert {:error, %ErrorMessage{code: :not_found}} =
               S3.copy_object("test-bucket", "test-object", "test-bucket", "nonexistent",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "presign/4" do
    test "returns mocked presigned URL with variable arity" do
      Sandbox.set_presign_responses([
        {"test-bucket",
         fn ->
           %{
             key: "test-object",
             url: "https://example.com/test-object?signature=fake",
             expires_in: 60,
             expires_at: ~U[2025-08-30 01:00:00.000000Z]
           }
         end}
      ])

      assert %{
               key: "test-object",
               url: "https://example.com/test-object?signature=fake",
               expires_in: 60,
               expires_at: ~U[2025-08-30 01:00:00.000000Z]
             } = S3.presign("test-bucket", :post, "test-object", sandbox: [enabled: true])
    end
  end

  describe "presign_post/3" do
    test "returns mocked presigned POST config" do
      Sandbox.set_presign_post_responses([
        {"test-bucket",
         fn ->
           {:ok,
            %{
              fields: %{key: "test-object", policy: "base64policy"},
              url: "https://example.com",
              expires_in: 60,
              expires_at: ~U[2025-08-30 01:00:00.000000Z]
            }}
         end}
      ])

      assert {:ok,
              %{
                fields: %{key: "test-object"},
                url: "https://example.com",
                expires_in: 60
              }} = S3.presign_post("test-bucket", "test-object", sandbox: [enabled: true])
    end
  end

  describe "presign_part/5" do
    test "returns mocked presigned part URL" do
      Sandbox.set_presign_part_responses([
        {"test-bucket",
         fn ->
           %{
             key: "test-object",
             url: "https://example.com/test-object?uploadId=uid&partNumber=1",
             expires_in: 60,
             expires_at: ~U[2025-08-30 01:00:00.000000Z]
           }
         end}
      ])

      assert %{
               key: "test-object",
               url: url,
               expires_in: 60
             } =
               S3.presign_part("test-bucket", "test-object", "upload-id", 1,
                 sandbox: [enabled: true]
               )

      assert url =~ "example.com"
    end
  end

  describe "create_multipart_upload/3" do
    test "returns upload metadata" do
      Sandbox.set_create_multipart_upload_responses([
        {"test-bucket",
         fn ->
           {:ok,
            %{
              bucket: "test-bucket",
              key: "test-object",
              upload_id: "upload_id_123"
            }}
         end}
      ])

      assert {:ok, %{bucket: "test-bucket", key: "test-object", upload_id: "upload_id_123"}} =
               S3.create_multipart_upload("test-bucket", "test-object", sandbox: [enabled: true])
    end

    test "returns error on failure" do
      Sandbox.set_create_multipart_upload_responses([
        {"test-bucket",
         fn ->
           {:error,
            %ErrorMessage{
              code: :service_unavailable,
              message: "service temporarily unavailable"
            }}
         end}
      ])

      assert {:error, %ErrorMessage{code: :service_unavailable}} =
               S3.create_multipart_upload("test-bucket", "test-object", sandbox: [enabled: true])
    end
  end

  describe "abort_multipart_upload/4" do
    test "returns ok tuple on success" do
      Sandbox.set_abort_multipart_upload_responses([
        {"test-bucket",
         fn ->
           {:ok, %{date: "Fri, 18 Aug 2023 10:32:49 GMT"}}
         end}
      ])

      assert {:ok, %{date: "Fri, 18 Aug 2023 10:32:49 GMT"}} =
               S3.abort_multipart_upload("test-bucket", "test-object", "upload_id_123",
                 sandbox: [enabled: true]
               )
    end

    test "returns error on failure" do
      Sandbox.set_abort_multipart_upload_responses([
        {"test-bucket",
         fn ->
           {:error,
            %ErrorMessage{
              code: :service_unavailable,
              message: "service temporarily unavailable"
            }}
         end}
      ])

      assert {:error, %ErrorMessage{code: :service_unavailable}} =
               S3.abort_multipart_upload("test-bucket", "test-object", "upload_id_123",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "upload_part/6" do
    test "returns ok on success" do
      Sandbox.set_upload_part_responses([
        {"test-bucket",
         fn ->
           {:ok, %{etag: "etag", content_length: 0}}
         end}
      ])

      assert {:ok, %{etag: "etag", content_length: 0}} =
               S3.upload_part("test-bucket", "test-object", "upload_id", 1, "content",
                 sandbox: [enabled: true]
               )
    end

    test "returns error on failure" do
      Sandbox.set_upload_part_responses([
        {"test-bucket",
         fn ->
           {:error,
            %ErrorMessage{
              code: :not_found,
              message: "object not found"
            }}
         end}
      ])

      assert {:error, %ErrorMessage{code: :not_found}} =
               S3.upload_part("test-bucket", "test-object", "upload_id", 1, "content",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "list_parts/5" do
    test "returns list of parts on success" do
      Sandbox.set_list_parts_responses([
        {"test-bucket",
         fn ->
           {:ok, [%{part_number: 1, size: 5_247_794, etag: "etag_123"}]}
         end}
      ])

      assert {:ok, [%{part_number: 1, size: 5_247_794, etag: "etag_123"}]} =
               S3.list_parts("test-bucket", "test-object", "upload_id_123", nil,
                 sandbox: [enabled: true]
               )
    end

    test "returns error when upload not found" do
      Sandbox.set_list_parts_responses([
        {"test-bucket",
         fn ->
           {:error,
            %ErrorMessage{
              code: :not_found,
              message: "object not found"
            }}
         end}
      ])

      assert {:error, %ErrorMessage{code: :not_found}} =
               S3.list_parts("test-bucket", "test-object", "upload_id", nil,
                 sandbox: [enabled: true]
               )
    end
  end

  describe "copy_part/8" do
    test "returns ok on success" do
      Sandbox.set_copy_part_responses([
        {"test-bucket",
         fn ->
           {:ok,
            %{
              last_modified: ~U[2025-08-30 01:00:00.000000Z],
              etag: "etag_123"
            }}
         end}
      ])

      assert {:ok,
              %{
                last_modified: ~U[2025-08-30 01:00:00.000000Z],
                etag: "etag_123"
              }} =
               S3.copy_part(
                 "test-bucket",
                 "dest.txt",
                 "test-bucket",
                 "test-object",
                 "upload_id_123",
                 1,
                 0..99,
                 sandbox: [enabled: true]
               )
    end

    test "returns error on failure" do
      Sandbox.set_copy_part_responses([
        {"test-bucket",
         fn ->
           {:error,
            %ErrorMessage{code: :service_unavailable, message: "service temporarily unavailable"}}
         end}
      ])

      assert {:error, %ErrorMessage{code: :service_unavailable}} =
               S3.copy_part(
                 "test-bucket",
                 "dest.txt",
                 "test-bucket",
                 "test-object",
                 "upload_id_123",
                 2,
                 0..99,
                 sandbox: [enabled: true]
               )
    end
  end

  describe "copy_parts/7" do
    test "returns ok on success" do
      Sandbox.set_copy_parts_responses([
        {"test-bucket",
         fn ->
           {:ok, [{1, "etag_1"}, {2, "etag_2"}]}
         end}
      ])

      assert {:ok, [{1, "etag_1"}, {2, "etag_2"}]} =
               S3.copy_parts(
                 "test-bucket",
                 "test-object",
                 "test-bucket",
                 "test-object",
                 "upload_id",
                 123,
                 sandbox: [enabled: true]
               )
    end

    test "returns error on failure" do
      Sandbox.set_copy_parts_responses([
        {"test-bucket",
         fn ->
           {:error,
            %ErrorMessage{code: :service_unavailable, message: "service temporarily unavailable"}}
         end}
      ])

      assert {:error, %ErrorMessage{code: :service_unavailable}} =
               S3.copy_parts(
                 "test-bucket",
                 "test-object",
                 "test-bucket",
                 "test-object",
                 "upload_id",
                 123,
                 sandbox: [enabled: true]
               )
    end
  end

  describe "complete_multipart_upload/5" do
    test "returns file metadata on success" do
      Sandbox.set_complete_multipart_upload_responses([
        {"test-bucket",
         fn ->
           {:ok,
            %{
              location: "https://s3.amazonaws.com/test-bucket/test-object",
              bucket: "test-bucket",
              key: "test-object",
              etag: "final-etag"
            }}
         end}
      ])

      assert {:ok,
              %{
                location: "https://s3.amazonaws.com/test-bucket/test-object",
                bucket: "test-bucket",
                key: "test-object",
                etag: "final-etag"
              }} =
               S3.complete_multipart_upload(
                 "test-bucket",
                 "test-object",
                 "upload_id_123",
                 [{1, "etag_123"}],
                 sandbox: [enabled: true]
               )
    end

    test "returns error on failure" do
      Sandbox.set_complete_multipart_upload_responses([
        {"test-bucket",
         fn ->
           {:error,
            %ErrorMessage{
              code: :service_unavailable,
              message: "service temporarily unavailable"
            }}
         end}
      ])

      assert {:error, %ErrorMessage{code: :service_unavailable}} =
               S3.complete_multipart_upload(
                 "test-bucket",
                 "test-object",
                 "bad_upload_id",
                 [{1, "etag"}],
                 sandbox: [enabled: true]
               )
    end
  end

  # S3 EventBridge notification functions

  describe "enable_event_bridge/2" do
    test "returns mocked success" do
      Sandbox.set_enable_event_bridge_responses([
        {"test-bucket", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} = S3.enable_event_bridge("test-bucket", sandbox: [enabled: true])
    end
  end

  describe "disable_event_bridge/2" do
    test "returns mocked success" do
      Sandbox.set_disable_event_bridge_responses([
        {"test-bucket", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} = S3.disable_event_bridge("test-bucket", sandbox: [enabled: true])
    end
  end

  describe "get_notification_configuration/2" do
    test "returns mocked configuration" do
      Sandbox.set_get_notification_configuration_responses([
        {"test-bucket", fn -> {:ok, %{event_bridge_configuration: %{}}} end}
      ])

      assert {:ok, %{event_bridge_configuration: %{}}} =
               S3.get_notification_configuration("test-bucket", sandbox: [enabled: true])
    end

    test "returns mocked configuration with EventBridge disabled" do
      Sandbox.set_get_notification_configuration_responses([
        {"test-bucket", fn -> {:ok, %{event_bridge_configuration: nil}} end}
      ])

      assert {:ok, %{event_bridge_configuration: nil}} =
               S3.get_notification_configuration("test-bucket", sandbox: [enabled: true])
    end
  end

  describe "head_bucket/2" do
    test "returns mocked headers" do
      Sandbox.set_head_bucket_responses([
        {"test-bucket", fn -> {:ok, %{x_amz_bucket_region: "us-east-1"}} end}
      ])

      assert {:ok, %{x_amz_bucket_region: "us-east-1"}} =
               S3.head_bucket("test-bucket", sandbox: [enabled: true])
    end

    test "returns error when bucket does not exist" do
      Sandbox.set_head_bucket_responses([
        {"test-bucket",
         fn -> {:error, %ErrorMessage{code: :not_found, message: "bucket not found"}} end}
      ])

      assert {:error, %ErrorMessage{code: :not_found}} =
               S3.head_bucket("test-bucket", sandbox: [enabled: true])
    end
  end

  describe "put_public_access_block/2" do
    test "returns mocked success" do
      Sandbox.set_put_public_access_block_responses([
        {"test-bucket", fn -> {:ok, %{x_amz_request_id: "req-1"}} end}
      ])

      assert {:ok, %{x_amz_request_id: "req-1"}} =
               S3.put_public_access_block("test-bucket", sandbox: [enabled: true])
    end
  end

  describe "put_bucket_encryption/2" do
    test "returns mocked success" do
      Sandbox.set_put_bucket_encryption_responses([
        {"test-bucket", fn -> {:ok, %{x_amz_request_id: "req-2"}} end}
      ])

      assert {:ok, %{x_amz_request_id: "req-2"}} =
               S3.put_bucket_encryption("test-bucket", sandbox: [enabled: true])
    end
  end

  describe "put_bucket_lifecycle_configuration/3" do
    test "returns mocked success" do
      Sandbox.set_put_bucket_lifecycle_configuration_responses([
        {"test-bucket", fn -> {:ok, %{rule_count: 1}} end}
      ])

      rules = [%{id: "r1", filter: %{prefix: "logs/"}, expiration: %{days: 30}}]

      assert {:ok, %{rule_count: 1}} =
               S3.put_bucket_lifecycle_configuration("test-bucket", rules,
                 sandbox: [enabled: true]
               )
    end
  end

  describe "delete_objects/3" do
    test "keys off the bucket" do
      Sandbox.set_delete_objects_responses([
        {"my-bucket", fn -> {:ok, %{deleted: [%{key: "a.txt"}], error: []}} end}
      ])

      assert {:ok, %{deleted: [%{key: "a.txt"}], error: []}} =
               S3.delete_objects("my-bucket", ["a.txt"], sandbox: [enabled: true])
    end
  end
end
