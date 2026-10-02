if Code.ensure_loaded?(SandboxRegistry) do
  defmodule AwsSDK.S3.Sandbox do
    @moduledoc false

    # Every operation keys on its bucket (the copy operations key on the
    # *destination* bucket), so registered keys are bucket names or regexes.

    @registry :aws_s3_sandbox

    alias AwsSDK.Sandbox

    def start_link, do: Sandbox.start_link(@registry)

    @spec disable_aws_s3_sandbox(map) :: :ok
    def disable_aws_s3_sandbox(_context), do: Sandbox.disable(@registry, __MODULE__)

    @spec sandbox_disabled? :: boolean
    def sandbox_disabled?, do: Sandbox.disabled?(@registry, __MODULE__)

    def list_buckets_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_buckets, :*, binding)
    end

    def set_list_buckets_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_buckets, entries)
    end

    def create_bucket_response(bucket, opts) do
      binding = [bucket: bucket, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_bucket, bucket, binding)
    end

    def set_create_bucket_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_bucket, entries)
    end

    def delete_bucket_response(bucket, opts) do
      binding = [bucket: bucket, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_bucket, bucket, binding)
    end

    def set_delete_bucket_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_bucket, entries)
    end

    def head_bucket_response(bucket, opts) do
      binding = [bucket: bucket, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :head_bucket, bucket, binding)
    end

    def set_head_bucket_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :head_bucket, entries)
    end

    def put_object_response(bucket, key, body, opts) do
      binding = [bucket: bucket, key: key, body: body, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :put_object, bucket, binding)
    end

    def set_put_object_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :put_object, entries)
    end

    def head_object_response(bucket, key, opts) do
      binding = [bucket: bucket, key: key, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :head_object, bucket, binding)
    end

    def set_head_object_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :head_object, entries)
    end

    def delete_object_response(bucket, key, opts) do
      binding = [bucket: bucket, key: key, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_object, bucket, binding)
    end

    def set_delete_object_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_object, entries)
    end

    def delete_objects_response(bucket, objects, opts) do
      binding = [bucket: bucket, objects: objects, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_objects, bucket, binding)
    end

    def set_delete_objects_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_objects, entries)
    end

    def get_object_response(bucket, key, opts) do
      binding = [bucket: bucket, key: key, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_object, bucket, binding)
    end

    def set_get_object_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_object, entries)
    end

    def list_objects_response(bucket, opts) do
      binding = [bucket: bucket, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_objects, bucket, binding)
    end

    def set_list_objects_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_objects, entries)
    end

    def copy_object_response(dest_bucket, dest_key, src_bucket, src_key, opts) do
      binding = [
        dest_bucket: dest_bucket,
        dest_key: dest_key,
        src_bucket: src_bucket,
        src_key: src_key,
        opts: opts
      ]

      Sandbox.apply(@registry, __MODULE__, :copy_object, dest_bucket, binding)
    end

    def set_copy_object_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :copy_object, entries)
    end

    def presign_response(bucket, http_method, key, opts) do
      binding = [bucket: bucket, http_method: http_method, key: key, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :presign, bucket, binding)
    end

    def set_presign_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :presign, entries)
    end

    def presign_post_response(bucket, key, opts) do
      binding = [bucket: bucket, key: key, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :presign_post, bucket, binding)
    end

    def set_presign_post_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :presign_post, entries)
    end

    def presign_part_response(bucket, object, upload_id, part_number, opts) do
      binding = [
        bucket: bucket,
        object: object,
        upload_id: upload_id,
        part_number: part_number,
        opts: opts
      ]

      Sandbox.apply(@registry, __MODULE__, :presign_part, bucket, binding)
    end

    def set_presign_part_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :presign_part, entries)
    end

    def create_multipart_upload_response(bucket, key, opts) do
      binding = [bucket: bucket, key: key, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_multipart_upload, bucket, binding)
    end

    def set_create_multipart_upload_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_multipart_upload, entries)
    end

    def abort_multipart_upload_response(bucket, key, upload_id, opts) do
      binding = [bucket: bucket, key: key, upload_id: upload_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :abort_multipart_upload, bucket, binding)
    end

    def set_abort_multipart_upload_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :abort_multipart_upload, entries)
    end

    def upload_part_response(bucket, key, upload_id, part_number, body, opts) do
      binding = [
        bucket: bucket,
        key: key,
        upload_id: upload_id,
        part_number: part_number,
        body: body,
        opts: opts
      ]

      Sandbox.apply(@registry, __MODULE__, :upload_part, bucket, binding)
    end

    def set_upload_part_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :upload_part, entries)
    end

    def list_parts_response(bucket, key, upload_id, part_number_marker, opts) do
      binding = [
        bucket: bucket,
        key: key,
        upload_id: upload_id,
        part_number_marker: part_number_marker,
        opts: opts
      ]

      Sandbox.apply(@registry, __MODULE__, :list_parts, bucket, binding)
    end

    def set_list_parts_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_parts, entries)
    end

    def copy_part_response(
          dest_bucket,
          dest_key,
          src_bucket,
          src_key,
          upload_id,
          part_number,
          src_range,
          opts
        ) do
      binding = [
        dest_bucket: dest_bucket,
        dest_key: dest_key,
        src_bucket: src_bucket,
        src_key: src_key,
        upload_id: upload_id,
        part_number: part_number,
        src_range: src_range,
        opts: opts
      ]

      Sandbox.apply(@registry, __MODULE__, :copy_part, dest_bucket, binding)
    end

    def set_copy_part_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :copy_part, entries)
    end

    def copy_parts_response(
          dest_bucket,
          dest_key,
          src_bucket,
          src_key,
          upload_id,
          content_length,
          opts
        ) do
      binding = [
        dest_bucket: dest_bucket,
        dest_key: dest_key,
        src_bucket: src_bucket,
        src_key: src_key,
        upload_id: upload_id,
        content_length: content_length,
        opts: opts
      ]

      Sandbox.apply(@registry, __MODULE__, :copy_parts, dest_bucket, binding)
    end

    def set_copy_parts_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :copy_parts, entries)
    end

    def complete_multipart_upload_response(bucket, key, upload_id, parts, opts) do
      binding = [bucket: bucket, key: key, upload_id: upload_id, parts: parts, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :complete_multipart_upload, bucket, binding)
    end

    def set_complete_multipart_upload_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :complete_multipart_upload, entries)
    end

    def enable_event_bridge_response(bucket, opts) do
      binding = [bucket: bucket, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :enable_event_bridge, bucket, binding)
    end

    def set_enable_event_bridge_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :enable_event_bridge, entries)
    end

    def disable_event_bridge_response(bucket, opts) do
      binding = [bucket: bucket, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :disable_event_bridge, bucket, binding)
    end

    def set_disable_event_bridge_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :disable_event_bridge, entries)
    end

    def get_notification_configuration_response(bucket, opts) do
      binding = [bucket: bucket, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_notification_configuration, bucket, binding)
    end

    def set_get_notification_configuration_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_notification_configuration, entries)
    end

    def put_public_access_block_response(bucket, opts) do
      binding = [bucket: bucket, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :put_public_access_block, bucket, binding)
    end

    def set_put_public_access_block_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :put_public_access_block, entries)
    end

    def put_bucket_encryption_response(bucket, opts) do
      binding = [bucket: bucket, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :put_bucket_encryption, bucket, binding)
    end

    def set_put_bucket_encryption_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :put_bucket_encryption, entries)
    end

    def put_bucket_lifecycle_configuration_response(bucket, rules, opts) do
      binding = [bucket: bucket, rules: rules, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :put_bucket_lifecycle_configuration, bucket, binding)
    end

    def set_put_bucket_lifecycle_configuration_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :put_bucket_lifecycle_configuration, entries)
    end

    def put_bucket_versioning_response(bucket, status, opts) do
      binding = [bucket: bucket, status: status, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :put_bucket_versioning, bucket, binding)
    end

    def set_put_bucket_versioning_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :put_bucket_versioning, entries)
    end
  end
end
