defmodule AwsSDK.S3.XMLParser do
  @moduledoc false

  import SweetXml, only: [sigil_x: 2, xpath: 2, xpath: 3]

  @doc """
  Parses a `CopyObjectResult` XML response.

  ## Examples

      AwsSDK.S3.XMLParser.parse_copy_object_result(
        ~s(<CopyObjectResult><ETag>"9a03"</ETag><LastModified>2026-01-01T00:00:00.000Z</LastModified></CopyObjectResult>)
      )
      #=> %{
      #=>   etag: "\"9a03\"",
      #=>   last_modified: "2026-01-01T00:00:00.000Z",
      #=>   checksum_crc32: "",
      #=>   checksum_sha256: "",
      #=>   checksum_type: ""
      #=>   # ...one key per documented checksum algorithm
      #=> }

  S3 can return a 200 whose body is an `<Error>`; that case yields
  `{:error, %ErrorMessage{}}` instead of a map.
  """
  def parse_copy_object_result(xml) do
    doc = SweetXml.parse(xml)

    case embedded_error(doc) do
      nil ->
        %{
          etag: xpath(doc, ~x"//CopyObjectResult/ETag/text()"s),
          last_modified: xpath(doc, ~x"//CopyObjectResult/LastModified/text()"s),
          checksum_crc32: xpath(doc, ~x"//CopyObjectResult/ChecksumCRC32/text()"so),
          checksum_crc32c: xpath(doc, ~x"//CopyObjectResult/ChecksumCRC32C/text()"so),
          checksum_crc64nvme: xpath(doc, ~x"//CopyObjectResult/ChecksumCRC64NVME/text()"so),
          checksum_sha1: xpath(doc, ~x"//CopyObjectResult/ChecksumSHA1/text()"so),
          checksum_sha256: xpath(doc, ~x"//CopyObjectResult/ChecksumSHA256/text()"so),
          checksum_sha512: xpath(doc, ~x"//CopyObjectResult/ChecksumSHA512/text()"so),
          checksum_md5: xpath(doc, ~x"//CopyObjectResult/ChecksumMD5/text()"so),
          checksum_xxhash64: xpath(doc, ~x"//CopyObjectResult/ChecksumXXHASH64/text()"so),
          checksum_xxhash3: xpath(doc, ~x"//CopyObjectResult/ChecksumXXHASH3/text()"so),
          checksum_xxhash128: xpath(doc, ~x"//CopyObjectResult/ChecksumXXHASH128/text()"so),
          checksum_type: xpath(doc, ~x"//CopyObjectResult/ChecksumType/text()"so)
        }

      error ->
        {:error, error}
    end
  end

  @doc """
  Parses a `NotificationConfiguration` XML response.

  Mirrors the wire: each configuration keeps AWS's singular element name,
  and `:event_bridge_configuration` is an empty map when the element is
  present and `nil` when it is not -- presence is the whole payload, since
  `EventBridgeConfiguration` has no members.

  ## Examples

      AwsSDK.S3.XMLParser.parse_notification_configuration(xml)
      #=> %{
      #=>   event_bridge_configuration: %{},
      #=>   topic_configuration: [],
      #=>   queue_configuration: [
      #=>     %{
      #=>       id: "uploads-to-sqs",
      #=>       queue: "arn:aws:sqs:us-east-1:123456789012:uploads",
      #=>       event: ["s3:ObjectCreated:*"],
      #=>       filter: %{s3_key: %{filter_rule: [%{name: "prefix", value: "incoming/"}]}}
      #=>     }
      #=>   ],
      #=>   cloud_function_configuration: []
      #=> }

  `:event_bridge_configuration` is `%{}` when the element is present and
  `nil` when it is absent -- `EventBridgeConfiguration` has no members, so
  presence is the whole payload.
  """
  @spec parse_notification_configuration(xml :: binary()) :: map()
  def parse_notification_configuration(xml) do
    doc = SweetXml.parse(xml)

    %{
      event_bridge_configuration:
        if(xpath(doc, ~x"//NotificationConfiguration/EventBridgeConfiguration"o), do: %{}),
      topic_configuration:
        xpath(doc, ~x"//NotificationConfiguration/TopicConfiguration"l,
          id: ~x"./Id/text()"so,
          topic: ~x"./Topic/text()"so,
          # The wire element is the singular `Event`, repeated.
          event: ~x"./Event/text()"sl,
          filter: [
            ~x"./Filter"o,
            s3_key: [
              ~x"./S3Key"o,
              filter_rule: [
                ~x"./FilterRule"l,
                name: ~x"./Name/text()"so,
                value: ~x"./Value/text()"so
              ]
            ]
          ]
        ),
      queue_configuration:
        xpath(doc, ~x"//NotificationConfiguration/QueueConfiguration"l,
          id: ~x"./Id/text()"so,
          queue: ~x"./Queue/text()"so,
          event: ~x"./Event/text()"sl,
          filter: [
            ~x"./Filter"o,
            s3_key: [
              ~x"./S3Key"o,
              filter_rule: [
                ~x"./FilterRule"l,
                name: ~x"./Name/text()"so,
                value: ~x"./Value/text()"so
              ]
            ]
          ]
        ),
      # The wire elements are `CloudFunctionConfiguration` / `CloudFunction`;
      # `LambdaFunctionConfiguration` is the model name, not the XML name.
      cloud_function_configuration:
        xpath(doc, ~x"//NotificationConfiguration/CloudFunctionConfiguration"l,
          id: ~x"./Id/text()"so,
          cloud_function: ~x"./CloudFunction/text()"so,
          event: ~x"./Event/text()"sl,
          filter: [
            ~x"./Filter"o,
            s3_key: [
              ~x"./S3Key"o,
              filter_rule: [
                ~x"./FilterRule"l,
                name: ~x"./Name/text()"so,
                value: ~x"./Value/text()"so
              ]
            ]
          ]
        )
    }
  end

  @doc """
  Parses a `ListAllMyBucketsResult` XML response.

  Returns `%{buckets: [...], owner: %{id, display_name}}`.

  ## Examples

      AwsSDK.S3.XMLParser.parse_list_buckets(xml)
      #=> %{
      #=>   buckets: %{
      #=>     bucket: [
      #=>       %{
      #=>         name: "uploads",
      #=>         creation_date: "2026-01-01T00:00:00.000Z",
      #=>         bucket_region: "us-east-1",
      #=>         bucket_arn: ""
      #=>       }
      #=>     ]
      #=>   },
      #=>   owner: %{id: "abc", display_name: "example"},
      #=>   continuation_token: "",
      #=>   prefix: ""
      #=> }

  `<Buckets>` is a wrapper holding repeated `<Bucket>` elements, so the list
  sits under `buckets.bucket` rather than collapsing to a bare list.
  """
  def parse_list_buckets(xml) do
    doc = SweetXml.parse(xml)

    %{
      # `Buckets` is a wrapper holding repeated `Bucket` elements, so it stays
      # a structure with a :bucket list rather than collapsing to a bare list.
      buckets: %{
        bucket:
          xpath(doc, ~x"//ListAllMyBucketsResult/Buckets/Bucket"l,
            name: ~x"./Name/text()"s,
            creation_date: ~x"./CreationDate/text()"s,
            bucket_region: ~x"./BucketRegion/text()"so,
            bucket_arn: ~x"./BucketArn/text()"so
          )
      },
      owner:
        xpath(doc, ~x"//ListAllMyBucketsResult/Owner"o,
          id: ~x"./ID/text()"s,
          display_name: ~x"./DisplayName/text()"s
        ),
      continuation_token: xpath(doc, ~x"//ListAllMyBucketsResult/ContinuationToken/text()"so),
      prefix: xpath(doc, ~x"//ListAllMyBucketsResult/Prefix/text()"so)
    }
  end

  @doc """
  Parses a `ListBucketResult` (v2) XML response.

  Returns `%{contents: [...], is_truncated, key_count, max_keys, name, prefix,
  continuation_token, next_continuation_token}`.

  ## Examples

      AwsSDK.S3.XMLParser.parse_list_objects(xml)
      #=> %{
      #=>   name: "uploads",
      #=>   prefix: "reports/",
      #=>   delimiter: "/",
      #=>   key_count: 1,
      #=>   max_keys: 1000,
      #=>   is_truncated: false,
      #=>   continuation_token: "",
      #=>   next_continuation_token: "",
      #=>   contents: [
      #=>     %{
      #=>       key: "reports/jan.csv",
      #=>       last_modified: "2026-01-01T00:00:00.000Z",
      #=>       etag: "\"9a03\"",
      #=>       size: 18,
      #=>       storage_class: "STANDARD",
      #=>       checksum_algorithm: [],
      #=>       owner: nil,
      #=>       restore_status: nil
      #=>     }
      #=>   ],
      #=>   common_prefixes: [%{prefix: "reports/2025/"}]
      #=> }

  Each `CommonPrefixes` entry is a structure with a `:prefix` member, not a
  bare string. `:key_count`, `:max_keys` and `:size` are cast to integers
  per the AWS model; `:checksum_algorithm` is a list on an Object, unlike
  the singular String of the same name in `parse_list_parts/1`.
  """
  def parse_list_objects(xml) do
    doc = SweetXml.parse(xml)

    %{
      name: xpath(doc, ~x"//ListBucketResult/Name/text()"s),
      prefix: xpath(doc, ~x"//ListBucketResult/Prefix/text()"s),
      key_count: xpath(doc, ~x"//ListBucketResult/KeyCount/text()"oi),
      max_keys: xpath(doc, ~x"//ListBucketResult/MaxKeys/text()"oi),
      is_truncated: to_bool(xpath(doc, ~x"//ListBucketResult/IsTruncated/text()"s)),
      continuation_token: xpath(doc, ~x"//ListBucketResult/ContinuationToken/text()"so),
      next_continuation_token: xpath(doc, ~x"//ListBucketResult/NextContinuationToken/text()"so),
      delimiter: xpath(doc, ~x"//ListBucketResult/Delimiter/text()"so),
      encoding_type: xpath(doc, ~x"//ListBucketResult/EncodingType/text()"so),
      start_after: xpath(doc, ~x"//ListBucketResult/StartAfter/text()"so),
      # `CommonPrefixes` repeats inline rather than sitting in a wrapper, and
      # each one is a CommonPrefix structure, not a bare string.
      common_prefixes:
        xpath(doc, ~x"//ListBucketResult/CommonPrefixes"l, prefix: ~x"./Prefix/text()"so),
      contents:
        xpath(doc, ~x"//ListBucketResult/Contents"l,
          key: ~x"./Key/text()"s,
          last_modified: ~x"./LastModified/text()"s,
          etag: ~x"./ETag/text()"s,
          size: ~x"./Size/text()"oi,
          storage_class: ~x"./StorageClass/text()"s,
          # On `Object` this is an array, unlike the singular String of the
          # same name on `ListPartsResult`.
          checksum_algorithm: ~x"./ChecksumAlgorithm/text()"sl,
          checksum_type: ~x"./ChecksumType/text()"so,
          owner: [
            ~x"./Owner"o,
            id: ~x"./ID/text()"so,
            display_name: ~x"./DisplayName/text()"so
          ],
          restore_status: [
            ~x"./RestoreStatus"o,
            is_restore_in_progress: ~x"./IsRestoreInProgress/text()"so,
            restore_expiry_date: ~x"./RestoreExpiryDate/text()"so
          ]
        )
    }
  end

  @doc """
  Parses an `InitiateMultipartUploadResult` XML response.

  Returns `%{bucket, key, upload_id}`.

  ## Examples

      AwsSDK.S3.XMLParser.parse_initiate_multipart(
        ~s(<InitiateMultipartUploadResult><Bucket>uploads</Bucket><Key>big.bin</Key><UploadId>2~kTX</UploadId></InitiateMultipartUploadResult>)
      )
      #=> %{bucket: "uploads", key: "big.bin", upload_id: "2~kTX"}
  """
  def parse_initiate_multipart(xml) do
    doc = SweetXml.parse(xml)

    %{
      bucket: xpath(doc, ~x"//InitiateMultipartUploadResult/Bucket/text()"s),
      key: xpath(doc, ~x"//InitiateMultipartUploadResult/Key/text()"s),
      upload_id: xpath(doc, ~x"//InitiateMultipartUploadResult/UploadId/text()"s)
    }
  end

  @doc """
  Parses a `ListPartsResult` XML response.

  Returns `%{parts: [...], is_truncated, part_number_marker, next_part_number_marker,
  max_parts, bucket, key, upload_id}`.

  ## Examples

      AwsSDK.S3.XMLParser.parse_list_parts(xml)
      #=> %{
      #=>   bucket: "uploads",
      #=>   key: "big.bin",
      #=>   upload_id: "2~kTX",
      #=>   max_parts: 1000,
      #=>   is_truncated: false,
      #=>   part_number_marker: "",
      #=>   next_part_number_marker: "",
      #=>   storage_class: "STANDARD",
      #=>   checksum_algorithm: "",
      #=>   initiator: %{id: "abc", display_name: "example"},
      #=>   owner: %{id: "abc", display_name: "example"},
      #=>   parts: [
      #=>     %{
      #=>       part_number: 1,
      #=>       size: 5_242_880,
      #=>       etag: "\"9a03\"",
      #=>       last_modified: "2026-01-01T00:00:00.000Z"
      #=>     }
      #=>   ]
      #=> }
  """
  def parse_list_parts(xml) do
    doc = SweetXml.parse(xml)

    %{
      bucket: xpath(doc, ~x"//ListPartsResult/Bucket/text()"s),
      key: xpath(doc, ~x"//ListPartsResult/Key/text()"s),
      upload_id: xpath(doc, ~x"//ListPartsResult/UploadId/text()"s),
      part_number_marker: xpath(doc, ~x"//ListPartsResult/PartNumberMarker/text()"so),
      next_part_number_marker: xpath(doc, ~x"//ListPartsResult/NextPartNumberMarker/text()"so),
      max_parts: xpath(doc, ~x"//ListPartsResult/MaxParts/text()"oi),
      is_truncated: to_bool(xpath(doc, ~x"//ListPartsResult/IsTruncated/text()"s)),
      storage_class: xpath(doc, ~x"//ListPartsResult/StorageClass/text()"so),
      # Singular String here, unlike the array on an Object in ListObjectsV2.
      checksum_algorithm: xpath(doc, ~x"//ListPartsResult/ChecksumAlgorithm/text()"so),
      checksum_type: xpath(doc, ~x"//ListPartsResult/ChecksumType/text()"so),
      initiator:
        xpath(doc, ~x"//ListPartsResult/Initiator"o,
          id: ~x"./ID/text()"so,
          display_name: ~x"./DisplayName/text()"so
        ),
      owner:
        xpath(doc, ~x"//ListPartsResult/Owner"o,
          id: ~x"./ID/text()"so,
          display_name: ~x"./DisplayName/text()"so
        ),
      parts:
        xpath(doc, ~x"//ListPartsResult/Part"l,
          part_number: ~x"./PartNumber/text()"oi,
          last_modified: ~x"./LastModified/text()"s,
          etag: ~x"./ETag/text()"s,
          size: ~x"./Size/text()"oi,
          checksum_crc32: ~x"./ChecksumCRC32/text()"so,
          checksum_crc32c: ~x"./ChecksumCRC32C/text()"so,
          checksum_crc64nvme: ~x"./ChecksumCRC64NVME/text()"so,
          checksum_sha1: ~x"./ChecksumSHA1/text()"so,
          checksum_sha256: ~x"./ChecksumSHA256/text()"so,
          checksum_sha512: ~x"./ChecksumSHA512/text()"so,
          checksum_md5: ~x"./ChecksumMD5/text()"so,
          checksum_xxhash64: ~x"./ChecksumXXHASH64/text()"so,
          checksum_xxhash3: ~x"./ChecksumXXHASH3/text()"so,
          checksum_xxhash128: ~x"./ChecksumXXHASH128/text()"so
        )
    }
  end

  @doc """
  Parses a `CopyPartResult` XML response.

  Returns `%{etag, last_modified}`.

  ## Examples

      AwsSDK.S3.XMLParser.parse_copy_part(
        ~s(<CopyPartResult><ETag>"9a03"</ETag><LastModified>2026-01-01T00:00:00.000Z</LastModified></CopyPartResult>)
      )
      #=> %{
      #=>   etag: "\"9a03\"",
      #=>   last_modified: "2026-01-01T00:00:00.000Z",
      #=>   checksum_crc32: "",
      #=>   checksum_sha256: ""
      #=>   # ...one key per documented checksum algorithm
      #=> }
  """
  def parse_copy_part(xml) do
    doc = SweetXml.parse(xml)

    %{
      etag: xpath(doc, ~x"//CopyPartResult/ETag/text()"s),
      last_modified: xpath(doc, ~x"//CopyPartResult/LastModified/text()"s),
      checksum_crc32: xpath(doc, ~x"//CopyPartResult/ChecksumCRC32/text()"so),
      checksum_crc32c: xpath(doc, ~x"//CopyPartResult/ChecksumCRC32C/text()"so),
      checksum_crc64nvme: xpath(doc, ~x"//CopyPartResult/ChecksumCRC64NVME/text()"so),
      checksum_sha1: xpath(doc, ~x"//CopyPartResult/ChecksumSHA1/text()"so),
      checksum_sha256: xpath(doc, ~x"//CopyPartResult/ChecksumSHA256/text()"so),
      checksum_sha512: xpath(doc, ~x"//CopyPartResult/ChecksumSHA512/text()"so),
      checksum_md5: xpath(doc, ~x"//CopyPartResult/ChecksumMD5/text()"so),
      checksum_xxhash64: xpath(doc, ~x"//CopyPartResult/ChecksumXXHASH64/text()"so),
      checksum_xxhash3: xpath(doc, ~x"//CopyPartResult/ChecksumXXHASH3/text()"so),
      checksum_xxhash128: xpath(doc, ~x"//CopyPartResult/ChecksumXXHASH128/text()"so)
    }
  end

  @doc """
  Parses a `CompleteMultipartUploadResult` XML response.

  Returns `%{location, bucket, key, etag}`.

  ## Examples

      AwsSDK.S3.XMLParser.parse_complete_multipart(xml)
      #=> %{
      #=>   location: "https://uploads.s3.us-east-1.amazonaws.com/big.bin",
      #=>   bucket: "uploads",
      #=>   key: "big.bin",
      #=>   etag: "\"9a03-2\""
      #=> }

  This is the operation most likely to return a 200 carrying an `<Error>`
  body, which yields `{:error, %ErrorMessage{}}`:

      AwsSDK.S3.XMLParser.parse_complete_multipart(
        ~s(<Error><Code>InternalError</Code><Message>We encountered an internal error.</Message></Error>)
      )
      #=> {:error, %ErrorMessage{}}
  """
  def parse_complete_multipart(xml) do
    doc = SweetXml.parse(xml)

    case embedded_error(doc) do
      nil ->
        %{
          location: xpath(doc, ~x"//CompleteMultipartUploadResult/Location/text()"s),
          bucket: xpath(doc, ~x"//CompleteMultipartUploadResult/Bucket/text()"s),
          key: xpath(doc, ~x"//CompleteMultipartUploadResult/Key/text()"s),
          etag: xpath(doc, ~x"//CompleteMultipartUploadResult/ETag/text()"s),
          checksum_crc32: xpath(doc, ~x"//CompleteMultipartUploadResult/ChecksumCRC32/text()"so),
          checksum_crc32c:
            xpath(doc, ~x"//CompleteMultipartUploadResult/ChecksumCRC32C/text()"so),
          checksum_crc64nvme:
            xpath(doc, ~x"//CompleteMultipartUploadResult/ChecksumCRC64NVME/text()"so),
          checksum_sha1: xpath(doc, ~x"//CompleteMultipartUploadResult/ChecksumSHA1/text()"so),
          checksum_sha256:
            xpath(doc, ~x"//CompleteMultipartUploadResult/ChecksumSHA256/text()"so),
          checksum_sha512:
            xpath(doc, ~x"//CompleteMultipartUploadResult/ChecksumSHA512/text()"so),
          checksum_md5: xpath(doc, ~x"//CompleteMultipartUploadResult/ChecksumMD5/text()"so),
          checksum_xxhash64:
            xpath(doc, ~x"//CompleteMultipartUploadResult/ChecksumXXHASH64/text()"so),
          checksum_xxhash3:
            xpath(doc, ~x"//CompleteMultipartUploadResult/ChecksumXXHASH3/text()"so),
          checksum_xxhash128:
            xpath(doc, ~x"//CompleteMultipartUploadResult/ChecksumXXHASH128/text()"so),
          checksum_type: xpath(doc, ~x"//CompleteMultipartUploadResult/ChecksumType/text()"so)
        }

      error ->
        {:error, error}
    end
  end

  # CopyObject and CompleteMultipartUpload can answer 200 OK with an <Error>
  # body -- AWS documents this explicitly and tells callers to parse the
  # contents. Without this the failed upload returned
  # `{:ok, %{location: "", bucket: "", key: "", etag: ""}}`.
  defp embedded_error(doc) do
    case xpath(doc, ~x"//Error/Code/text()"s) do
      "" ->
        nil

      code ->
        ErrorMessage.internal_server_error("s3 returned an error in a 200 response", %{
          code: code,
          message: xpath(doc, ~x"//Error/Message/text()"s),
          request_id: xpath(doc, ~x"//Error/RequestId/text()"s)
        })
    end
  end

  # S3 returns IsTruncated as "true"/"false" text.
  @doc """
  Parses the `<DeleteResult>` body a `DeleteObjects` call returns.
  """
  @spec parse_delete_result(binary()) :: %{deleted: [map()], error: [map()]}
  def parse_delete_result(xml) do
    deleted =
      xml
      |> xpath(~x"//DeleteResult/Deleted"l,
        key: ~x"./Key/text()"s,
        version_id: ~x"./VersionId/text()"so,
        delete_marker: ~x"./DeleteMarker/text()"so,
        delete_marker_version_id: ~x"./DeleteMarkerVersionId/text()"so
      )
      |> Enum.map(fn entry -> %{entry | delete_marker: to_bool(entry.delete_marker)} end)

    %{
      deleted: deleted,
      error:
        xpath(xml, ~x"//DeleteResult/Error"l,
          key: ~x"./Key/text()"s,
          version_id: ~x"./VersionId/text()"so,
          code: ~x"./Code/text()"so,
          message: ~x"./Message/text()"so
        )
    }
  end

  defp to_bool("true"), do: true
  defp to_bool("false"), do: false
  defp to_bool(_), do: false
end
