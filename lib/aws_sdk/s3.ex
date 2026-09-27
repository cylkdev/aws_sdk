defmodule AwsSDK.S3 do
  @moduledoc """
  `AwsSDK.S3` provides an API for working with S3 (Simple Storage Service).

  This module calls the AWS S3 REST/XML API directly via `AwsSDK.HTTP` and
  `AwsSDK.Signer` (through `AwsSDK.S3.Client`). It provides consistent error
  handling, response deserialization, and sandbox support for local
  development and testing.

  S3's public API is XML-only at the AWS wire level. The service model
  (`botocore/data/s3/2006-03-01/service-2.json`) declares
  `metadata.protocols = ["rest-xml"]`, and AWS does not expose a JSON
  alternative for S3 operations. The XML handling in this module is a
  consequence of AWS's protocol choice, not a library decision: per-
  operation HTTP shapes (path, method, headers), XML response bodies
  for list/describe-style calls, and header-only response payloads for
  write-style calls. XPath extraction runs in `AwsSDK.S3.XMLParser`;
  response-header-to-map conversion runs in `ExUtils.Serializer`.

  It is also the only service with first-class support for **presigned
  URLs** (via `presign/4` and `presign_part/5`), **presigned POST form
  policies** (via `presign_post/3`), and **streaming uploads** — pass an
  `Enumerable` of iodata chunks as the body to `put_object/4` or
  `upload_part/6` to avoid buffering large payloads in memory.

  ## Shared Options

  Credential and region options are flat top-level keys on every call.
  Each accepts a literal, a source tuple, or a list of sources (first
  non-nil wins). This mirrors `ExAws.Config`.

    - `:access_key_id` - AWS access key ID. Sources: literal binary,
      `{:system, "ENV"}`, `:instance_role`, `:ecs_task_role`,
      `{:awscli, profile}` / `{:awscli, profile, ttl_seconds}`, a module,
      or a list of any of these.

    - `:secret_access_key` - AWS secret access key. Same source vocabulary.

    - `:security_token` - STS session token. Same source vocabulary.

    - `:region` - AWS region. Same source vocabulary. Defaults to
      `AwsSDK.Config.region()`.

  If a source returns a map (e.g. `:instance_role` or `{:awscli, _}`),
  its fields are merged into the resolved config, so listing
  `:instance_role` under `:access_key_id` also populates
  `:secret_access_key` and `:security_token`.

  `{:awscli, _}` is **not** in the default chain — callers opt in
  explicitly. Reading `~/.aws/*` silently on server runtimes is surprising.

  The following options are also available for most functions:

    - `:s3` - A keyword list of S3-specific endpoint overrides. Supports
      `:scheme`, `:host`, `:port`, `:path_style`. Credentials are not
      read from this sub-list; use the top-level keys above.

    - `:sandbox` - A keyword list to override sandbox configuration. Each
      key falls back to the corresponding entry in `AwsSDK.Config.sandbox/0`.
        - `:enabled` - Whether sandbox mode is enabled.

  ## Sandbox

  This API provides a sandbox that you can use during development and testing
  to mock S3 operations without making real HTTP calls.

  Set `sandbox: [enabled: true]` to activate sandbox mode.

  ### Setup

  Add the following to your `test_helper.exs`:

      AwsSDK.S3.Sandbox.start_link()

  ### Usage

  Register mock responses in your test `setup` block, then pass
  `sandbox: [enabled: true]` to any S3 function:

      setup do
        AwsSDK.S3.Sandbox.set_get_object_responses([
          {"my-bucket", fn key -> {:ok, "content for \#{key}"} end}
        ])
      end

      test "gets an object" do
        assert {:ok, "content for my-key"} =
                 AwsSDK.S3.get_object("my-bucket", "my-key",
                   sandbox: [enabled: true]
                 )
      end

  ### Bucket Matching

  Each registration tuple has two elements:

    - A **bucket name** (exact string match) or a **regex** (`~r/pattern/`)
    - A **function** that returns the mocked response

  For `list_buckets`, pass a list of bare functions (no bucket tuple needed).

  ### Variable Arity

  Response functions support variable arity. For example,
  `set_get_object_responses/1` accepts functions with 0, 1, or 2 parameters:

      fn -> {:ok, "static"} end
      fn key -> {:ok, "content for \#{key}"} end
      fn key, opts -> {:ok, "content"} end
  """

  alias AwsSDK.{
    Client,
    Config,
    Operation,
    S3.Multipart,
    S3.XMLBuilder,
    S3.XMLParser,
    Signer
  }

  alias ExUtils.Serializer

  @service "s3"
  @sixty_four_mib 64 * 1_024 * 1_024
  @one_gib 1 * 1_024 * 1_024 * 1_024
  @sixty_seconds 60

  @doc """
  Returns a list of all buckets owned by the authenticated sender of the request.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:ListAllMyBuckets

  ## Arguments

    * `opts` - A keyword list of options.

  ## Options

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.list_buckets()
      {:ok, [%{name: "my-bucket", creation_date: "2024-01-01T00:00:00.000Z"}]}

  ## Examples

      AwsSDK.S3.list_buckets()
      #=> {:ok,
      #=>  %{
      #=>    buckets: %{
      #=>      bucket: [
      #=>        %{
      #=>          name: "uploads-bucket",
      #=>          creation_date: "2026-01-01T00:00:00.000Z",
      #=>          bucket_region: "us-east-1",
      #=>          bucket_arn: ""
      #=>        }
      #=>      ]
      #=>    },
      #=>    owner: %{id: "abc123...", display_name: "example"},
      #=>    continuation_token: "",
      #=>    prefix: ""
      #=>  }}

  `<Buckets>` is a wrapper element holding repeated `<Bucket>` entries, so
  the list sits under `buckets.bucket`.
  """
  @spec list_buckets(opts :: keyword()) :: {:ok, list()} | {:error, term()}
  def list_buckets(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_buckets_response(opts)
    else
      do_list_buckets(opts)
    end
  end

  @doc """
  Creates a bucket in the specified region.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:CreateBucket

  ## Arguments

    * `bucket` - The name of the bucket to create.
    * `opts` - A keyword list of options.

  ## Options

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.create_bucket("my-bucket")
      {:ok, %{location: "...", x_amz_request_id: "...", date: "..."}}

  ## Examples

      AwsSDK.S3.create_bucket("uploads-bucket")
      #=> {:ok, %{}}

      # Outside us-east-1 the region must be declared in the body.
      AwsSDK.S3.create_bucket("uploads-bucket", region: "eu-west-1")
      #=> {:ok, %{}}
  """
  @spec create_bucket(bucket :: binary(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def create_bucket(bucket, opts \\ []) do
    if sandbox?(opts) do
      sandbox_create_bucket_response(bucket, opts)
    else
      do_create_bucket(bucket, opts)
    end
  end

  @doc """
  Deletes an empty bucket.

  Returns `{:error, :not_found}` if the bucket does not exist and
  `{:error, :conflict}` if the bucket is not empty.

  ## Arguments

    * `bucket` - The name of the bucket to delete.
    * `opts` - A keyword list of options.

  ## Options

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.delete_bucket("my-bucket")
      {:ok, %{x_amz_request_id: "...", date: "..."}}

  ## Examples

      AwsSDK.S3.delete_bucket("uploads-bucket")
      #=> {:ok, %{}}

  The bucket must be empty.
  """
  @spec delete_bucket(bucket :: binary(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def delete_bucket(bucket, opts \\ []) do
    if sandbox?(opts) do
      sandbox_delete_bucket_response(bucket, opts)
    else
      do_delete_bucket(bucket, opts)
    end
  end

  @doc """
  Determines whether a bucket exists and the caller has permission to access it.

  Returns `{:ok, headers}` when the bucket exists and is accessible (the response
  body is empty; useful headers such as `x-amz-bucket-region` are returned).
  Returns `{:error, :not_found}` when the bucket does not exist or the caller
  lacks permission.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:ListBucket

  ## Arguments

    * `bucket` - The name of the bucket to check.
    * `opts` - A keyword list of options.

  ## Options

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.head_bucket("my-bucket")
      {:ok, %{x_amz_bucket_region: "us-east-1", x_amz_request_id: "...", date: "..."}}

  ## Examples

      AwsSDK.S3.head_bucket("uploads-bucket")
      #=> {:ok, %{}}

      AwsSDK.S3.head_bucket("does-not-exist")
      #=> {:error, %ErrorMessage{code: :not_found, message: "resource not found."}}

  HEAD carries no body, so existence is signalled by the tuple alone.
  """
  @spec head_bucket(bucket :: binary(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def head_bucket(bucket, opts \\ []) do
    if sandbox?(opts) do
      sandbox_head_bucket_response(bucket, opts)
    else
      do_head_bucket(bucket, opts)
    end
  end

  @doc """
  Uploads an object to a bucket.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:PutObject

  ## Arguments

    * `bucket` - The name of the bucket to upload to.
    * `key` - The key under which to store the object.
    * `body` - The content to upload (iodata, or an `Enumerable` of iodata chunks for streaming).
    * `opts` - A keyword list of options.

  ## Options

    * `:content_type` - Explicit `content-type` header for the object.
    * `:acl` - Canned ACL (maps to `x-amz-acl`).
    * `:headers` - Additional raw request headers.
    * `:if_none_match` - When `true`, adds an `if-none-match` header so S3
      rejects the request (with HTTP 412 Precondition Failed) if an object
      already exists at `key`. The 412 is translated to an
      `ErrorMessage` struct with `code: :conflict`. Skipped when the caller
      already supplied an `if-none-match` header in `:headers`.
    * `:if_none_match_pattern` - Overrides the value sent with `:if_none_match`.
      Defaults to `"*"` (matches any existing object).

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.put_object("my-bucket", "my-key", "hello world")
      {:ok, %{etag: "...", x_amz_request_id: "..."}}

      iex> AwsSDK.S3.put_object("my-bucket", "existing-key", "hello", if_none_match: true)
      {:error, %ErrorMessage{code: :conflict, message: "object already exists", ...}}

  ## Examples

      AwsSDK.S3.put_object("uploads-bucket", "reports/jan.csv", "id,total\n1,42\n",
        content_type: "text/csv"
      )
      #=> {:ok, %{}}

      # Server-side encryption with a KMS key.
      AwsSDK.S3.put_object("uploads-bucket", "secret.txt", "...",
        server_side_encryption: "aws:kms",
        ssekms_key_id: "arn:aws:kms:us-east-1:123456789012:key/abc"
      )
      #=> {:ok, %{}}

  S3 returns the ETag in a header rather than a body, so the result map is
  empty on success.
  """
  @spec put_object(
          bucket :: binary(),
          key :: binary(),
          body :: iodata() | Enumerable.t(),
          opts :: keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def put_object(bucket, key, body, opts \\ []) do
    if sandbox?(opts) do
      sandbox_put_object_response(bucket, key, body, opts)
    else
      do_put_object(bucket, key, body, opts)
    end
  end

  @doc """
  Returns the metadata of an object stored in S3 without returning the object itself.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:GetObject

  ## Arguments

    * `bucket` - The name of the bucket containing the object.
    * `key` - The key of the object to retrieve metadata for.
    * `opts` - A keyword list of options.

  ## Options

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.head_object("my-bucket", "my-key")
      {:ok, %{content_length: "1234", content_type: "application/json", ...}}

  ## Examples

      AwsSDK.S3.head_object("uploads-bucket", "reports/jan.csv")
      #=> {:ok,
      #=>  %{
      #=>    headers: [
      #=>      {"content-length", "18"},
      #=>      {"content-type", "text/csv"},
      #=>      {"etag", "\"9a0364b9e99bb480dd25e1f0284c8555\""},
      #=>      {"last-modified", "Thu, 01 Jan 2026 00:00:00 GMT"}
      #=>    ]
      #=>  }}

  Metadata only -- HEAD never returns the body. Use this to check existence
  or size without transferring the object.
  """
  @spec head_object(bucket :: binary(), key :: binary(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def head_object(bucket, key, opts \\ []) do
    if sandbox?(opts) do
      sandbox_head_object_response(bucket, key, opts)
    else
      do_head_object(bucket, key, opts)
    end
  end

  @doc """
  Deletes an object from a bucket.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:DeleteObject

  ## Arguments

    * `bucket` - The name of the bucket containing the object.
    * `key` - The key of the object to delete.
    * `opts` - A keyword list of options.

  ## Options

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.delete_object("my-bucket", "my-key")
      {:ok, ""}

  ## Examples

      AwsSDK.S3.delete_object("uploads-bucket", "reports/jan.csv")
      #=> {:ok, %{}}

  Deleting a key that does not exist also succeeds; S3 treats it as a no-op.
  """
  @spec delete_object(bucket :: binary(), key :: binary(), opts :: keyword()) ::
          {:ok, term()} | {:error, term()}
  def delete_object(bucket, key, opts \\ []) do
    if sandbox?(opts) do
      sandbox_delete_object_response(bucket, key, opts)
    else
      do_delete_object(bucket, key, opts)
    end
  end

  @doc """
  Deletes up to 1000 objects from a bucket in a single request.

  S3 reports per-key outcomes in the body — a 200 response can still carry
  per-key failures, so check `:error` before treating the batch as done.

  ## Arguments

    * `bucket` - The bucket name.
    * `objects` - List of keys (binaries) and/or `%{key:, version_id:}` maps.
    * `opts` - Options:
      * `:quiet` - Boolean; ask S3 to omit per-key success entries.

  ## Examples

      AwsSDK.S3.delete_objects("my-bucket", ["a.txt", %{key: "b.txt", version_id: "v1"}])
      #=> {:ok,
      #=>  %{
      #=>    deleted: [
      #=>      %{key: "a.txt", version_id: "", delete_marker: false, delete_marker_version_id: ""},
      #=>      %{key: "b.txt", version_id: "v1", delete_marker: false, delete_marker_version_id: ""}
      #=>    ],
      #=>    error: []
      #=>  }}
  """
  @spec delete_objects(bucket :: String.t(), objects :: [String.t() | map()], opts :: keyword()) ::
          {:ok, %{deleted: [map()], error: [map()]}} | {:error, term()}
  def delete_objects(bucket, [_ | _] = objects, opts \\ []) when is_binary(bucket) do
    if sandbox?(opts) do
      sandbox_delete_objects_response(bucket, objects, opts)
    else
      do_delete_objects(bucket, objects, opts)
    end
  end

  @doc """
  Returns the content of an object stored in S3.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:GetObject

  ## Arguments

    * `bucket` - The name of the bucket containing the object.
    * `key` - The key of the object to retrieve.
    * `opts` - A keyword list of options.

  ## Options

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.get_object("my-bucket", "my-key")
      {:ok, <<binary_content>>}

  ## Examples

      AwsSDK.S3.get_object("uploads-bucket", "reports/jan.csv")
      #=> {:ok, %{body: "id,total\n1,42\n", headers: [{"content-type", "text/csv"}]}}

      # Fetch a byte range.
      AwsSDK.S3.get_object("uploads-bucket", "big.bin", range: "bytes=0-1023")
      #=> {:ok, %{body: <<...1024 bytes...>>, headers: [...]}}

      # Stream to disk instead of buffering in memory.
      AwsSDK.S3.get_object("uploads-bucket", "big.bin", stream_to: "/tmp/big.bin")
      #=> {:ok, %{path: "/tmp/big.bin", headers: [...]}}
  """
  @spec get_object(bucket :: binary(), key :: binary(), opts :: keyword()) ::
          {:ok, binary()} | {:error, term()}
  def get_object(bucket, key, opts \\ []) do
    if sandbox?(opts) do
      sandbox_get_object_response(bucket, key, opts)
    else
      do_get_object(bucket, key, opts)
    end
  end

  @doc """
  Returns a list of objects in a bucket.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:ListBucket

  ## Arguments

    * `bucket` - The name of the bucket to list objects from.
    * `opts` - A keyword list of options.

  ## Options

    * `:prefix` - Limit the response to keys that begin with the specified prefix.
    * `:delimiter` - Groups keys that contain the delimiter into a single result.
    * `:max_keys` - Maximum number of keys returned (up to 1000).
    * `:start_after` - Start listing after this key.
    * `:continuation_token` - Pagination token from a previous response.
    * `:fetch_owner` - Whether to include bucket owner info.
    * `:encoding_type` - Encoding method for response keys.

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.list_objects("my-bucket")
      {:ok, [%{key: "my-key", size: "1234", ...}]}

  ## Examples

      AwsSDK.S3.list_objects("uploads-bucket", prefix: "reports/", delimiter: "/")
      #=> {:ok,
      #=>  %{
      #=>    name: "uploads-bucket",
      #=>    prefix: "reports/",
      #=>    delimiter: "/",
      #=>    key_count: 1,
      #=>    max_keys: 1000,
      #=>    is_truncated: false,
      #=>    continuation_token: nil,
      #=>    next_continuation_token: nil,
      #=>    contents: [
      #=>      %{
      #=>        key: "reports/jan.csv",
      #=>        last_modified: "2026-01-01T00:00:00.000Z",
      #=>        etag: "\"9a0364b9e99bb480dd25e1f0284c8555\"",
      #=>        size: 18,
      #=>        storage_class: "STANDARD",
      #=>        owner: nil,
      #=>        restore_status: nil
      #=>      }
      #=>    ],
      #=>    common_prefixes: [%{prefix: "reports/2025/"}]
      #=>  }}

  Each `:common_prefixes` entry is a `CommonPrefix` structure with a
  `:prefix` member, not a bare string. When `:is_truncated` is true, pass
  `:next_continuation_token` back as `:continuation_token`.
  """
  @spec list_objects(bucket :: binary(), opts :: keyword()) ::
          {:ok, list()} | {:error, term()}
  def list_objects(bucket, opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_objects_response(bucket, opts)
    else
      do_list_objects(bucket, opts)
    end
  end

  @doc """
  Copies an object from one bucket to another.

  ## Permissions

  To execute this request, you must have the following permissions:

    - s3:GetObject (on the source bucket)
    - s3:PutObject (on the destination bucket)

  ## Arguments

    * `dest_bucket` - The name of the destination bucket.
    * `dest_key` - The key for the copied object in the destination bucket.
    * `src_bucket` - The name of the source bucket.
    * `src_key` - The key of the object to copy from the source bucket.
    * `opts` - A keyword list of options.

  ## Options

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.copy_object("dest-bucket", "dest-key", "src-bucket", "src-key")
      {:ok, %{etag: "...", last_modified: "..."}}

  ## Examples

      AwsSDK.S3.copy_object("archive-bucket", "2026/jan.csv", "uploads-bucket", "reports/jan.csv")
      #=> {:ok,
      #=>  %{
      #=>    etag: "\"9a0364b9e99bb480dd25e1f0284c8555\"",
      #=>    last_modified: "2026-02-01T00:00:00.000Z",
      #=>    checksum_crc32: nil,
      #=>    checksum_sha256: nil
      #=>  }}

  Arguments are destination first, then source. Single-request copy is
  limited to 5 GB; use `copy_object_multipart/5` above that.

  S3 can return a 200 whose body is an `<Error>`; that is surfaced as
  `{:error, %ErrorMessage{}}` rather than being reported as success.
  """
  @spec copy_object(
          dest_bucket :: binary(),
          dest_key :: binary(),
          src_bucket :: binary(),
          src_key :: binary(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def copy_object(dest_bucket, dest_key, src_bucket, src_key, opts \\ []) do
    if sandbox?(opts) do
      sandbox_copy_object_response(dest_bucket, dest_key, src_bucket, src_key, opts)
    else
      do_copy_object(dest_bucket, dest_key, src_bucket, src_key, opts)
    end
  end

  @doc """
  Returns a presigned URL for an object.

  The presigned URL allows temporary access to the object without requiring
  AWS credentials from the requester.

  ## Permissions

  The credentials used to generate the presigned URL must have the permission
  required for the corresponding HTTP method:

    - `:get` — s3:GetObject
    - `:put` — s3:PutObject
    - `:delete` — s3:DeleteObject
    - `:head` — s3:GetObject

  ## Arguments

    * `bucket` - The name of the bucket containing the object.
    * `http_method` - The HTTP method to presign (e.g., `:get`, `:put`, `:post`, `:delete`, `:head`).
    * `key` - The key of the object.
    * `opts` - A keyword list of options.

  ## Options

    - `:expires_in` - The number of seconds until the presigned URL expires. Defaults to 60.
    - `:query_params` - Additional query parameters to include in the signed URL.

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.presign("my-bucket", :get, "my-key")
      %{key: "my-key", url: "https://...", expires_in: 60, expires_at: ~U[...]}

  ## Examples

      AwsSDK.S3.presign(:get, "uploads-bucket", "reports/jan.csv", expires_in: 900)
      #=> {:ok,
      #=>  "https://uploads-bucket.s3.us-east-1.amazonaws.com/reports/jan.csv" <>
      #=>    "?X-Amz-Algorithm=AWS4-HMAC-SHA256" <>
      #=>    "&X-Amz-Credential=AKIA1EXAMPLE%2F20260101%2Fus-east-1%2Fs3%2Faws4_request" <>
      #=>    "&X-Amz-Date=20260101T000000Z&X-Amz-Expires=900" <>
      #=>    "&X-Amz-SignedHeaders=host&X-Amz-Signature=8d1f..."}

      # A presigned upload URL.
      AwsSDK.S3.presign(:put, "uploads-bucket", "incoming/photo.jpg", expires_in: 300)
      #=> {:ok, "https://uploads-bucket.s3.us-east-1.amazonaws.com/incoming/photo.jpg?..."}

  Signing is local -- no request is made. The URL grants exactly the method
  it was signed for, and expires after `:expires_in` seconds (default 3600,
  maximum 604800).
  """
  @spec presign(bucket :: binary(), http_method :: atom(), key :: binary(), opts :: keyword()) ::
          map()
  def presign(bucket, http_method, key, opts \\ []) do
    if sandbox?(opts) do
      sandbox_presign_response(bucket, http_method, key, opts)
    else
      do_presign(bucket, http_method, key, opts)
    end
  end

  @doc """
  Returns a presigned POST configuration for uploading an object directly to S3.

  The presigned POST includes a URL and form fields that can be used in an
  HTML form or multipart upload to upload an object without server-side proxying.

  ## Permissions

  The credentials used to generate the presigned POST must have the following permission:

    - s3:PutObject

  ## Arguments

    * `bucket` - The name of the bucket to upload to.
    * `key` - The key under which the object will be stored.
    * `opts` - A keyword list of options.

  ## Options

    * `:expires_in` - The number of seconds until the presigned POST expires. Defaults to 60.
    * `:min_size` - Minimum allowed upload size in bytes. Defaults to 0.
    * `:max_size` - Maximum allowed upload size in bytes. Defaults to 1 GiB.
    * `:content_type` - Optional content type prefix for the upload condition.

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.presign_post("my-bucket", "my-key")
      {:ok, %{fields: %{...}, url: "https://...", expires_in: 60, expires_at: ~U[...]}}

  ## Examples

      AwsSDK.S3.presign_post("uploads-bucket", "incoming/photo.jpg",
        expires_in: 3600,
        conditions: [["content-length-range", 0, 10_485_760]]
      )
      #=> {:ok,
      #=>  %{
      #=>    url: "https://uploads-bucket.s3.us-east-1.amazonaws.com",
      #=>    fields: %{
      #=>      "key" => "incoming/photo.jpg",
      #=>      "policy" => "eyJleHBpcmF0aW9uIjoi...",
      #=>      "x-amz-algorithm" => "AWS4-HMAC-SHA256",
      #=>      "x-amz-credential" => "AKIA1EXAMPLE/20260101/us-east-1/s3/aws4_request",
      #=>      "x-amz-date" => "20260101T000000Z",
      #=>      "x-amz-signature" => "8d1f..."
      #=>    }
      #=>  }}

  For browser uploads: POST a multipart form to `:url` with every entry of
  `:fields` plus a trailing `file` part. The field names are literal AWS
  wire names (lowercase strings), not atoms.
  """
  @spec presign_post(bucket :: binary(), key :: binary(), opts :: keyword()) ::
          {:ok, map()}
  def presign_post(bucket, key, opts \\ []) do
    if sandbox?(opts) do
      sandbox_presign_post_response(bucket, key, opts)
    else
      do_presign_post(bucket, key, opts)
    end
  end

  @doc """
  Returns a presigned URL for uploading a part of a multipart upload.

  This is a convenience wrapper around `presign/4` that adds the required
  `uploadId` and `partNumber` query parameters for multipart upload parts.

  ## Permissions

  The credentials used to generate the presigned URL must have the following permission:

    - s3:PutObject

  ## Arguments

    * `bucket` - The name of the bucket.
    * `object` - The key of the object being uploaded.
    * `upload_id` - The upload ID of the multipart upload.
    * `part_number` - The part number of the part to upload.
    * `opts` - A keyword list of options.

  ## Options

  See `presign/4` for available options.

  ## Examples

      iex> AwsSDK.S3.presign_part("my-bucket", "my-key", "upload-id", 1)
      %{key: "my-key", url: "https://...", expires_in: 60, expires_at: ~U[...]}

  ## Examples

      {:ok, %{upload_id: upload_id}} =
        AwsSDK.S3.create_multipart_upload("uploads-bucket", "big.bin")

      AwsSDK.S3.presign_part("uploads-bucket", "big.bin", upload_id, 1, expires_in: 3600)
      #=> {:ok,
      #=>  "https://uploads-bucket.s3.us-east-1.amazonaws.com/big.bin" <>
      #=>    "?partNumber=1&uploadId=" <> upload_id <> "&X-Amz-Algorithm=..."}

  Lets a client upload one part directly. Part numbers run from 1 to 10000.
  """
  @spec presign_part(
          bucket :: binary(),
          object :: binary(),
          upload_id :: binary(),
          part_number :: integer(),
          opts :: keyword()
        ) :: map()
  def presign_part(bucket, object, upload_id, part_number, opts \\ []) do
    if sandbox?(opts) do
      sandbox_presign_part_response(bucket, object, upload_id, part_number, opts)
    else
      do_presign_part(bucket, object, upload_id, part_number, opts)
    end
  end

  @doc """
  Initiates a multipart upload and returns the upload ID.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:PutObject

  ## Arguments

    * `bucket` - The name of the bucket.
    * `key` - The key of the object to upload.
    * `opts` - A keyword list of options.

  ## Options

    - `:expires` - An expiry value for the multipart upload. Accepts a `DateTime`, an HTTP date
      string, or `nil` (defaults to 1 minute from now).

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.create_multipart_upload("my-bucket", "my-key")
      {:ok, %{upload_id: "...", bucket: "my-bucket", key: "my-key"}}

  ## Examples

      AwsSDK.S3.create_multipart_upload("uploads-bucket", "big.bin",
        content_type: "application/octet-stream"
      )
      #=> {:ok,
      #=>  %{
      #=>    bucket: "uploads-bucket",
      #=>    key: "big.bin",
      #=>    upload_id: "2~kTXQPYyIB8aQ0uQ8sYqLpXQ0nD8fEXAMPLE"
      #=>  }}

  An upload holds storage until completed or aborted; pair this with
  `abort_multipart_upload/4` on the failure path.
  """
  @spec create_multipart_upload(bucket :: binary(), key :: binary(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def create_multipart_upload(bucket, key, opts \\ []) do
    if sandbox?(opts) do
      sandbox_create_multipart_upload_response(bucket, key, opts)
    else
      do_create_multipart_upload(bucket, key, opts)
    end
  end

  @doc """
  Aborts a multipart upload.

  After aborting, any previously uploaded parts are deleted and no further
  parts can be uploaded using the same upload ID.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:AbortMultipartUpload

  ## Arguments

    * `bucket` - The name of the bucket.
    * `key` - The key of the object.
    * `upload_id` - The upload ID of the multipart upload to abort.
    * `opts` - A keyword list of options.

  ## Options

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.abort_multipart_upload("my-bucket", "my-key", "upload-id")
      {:ok, %{}}

  ## Examples

      AwsSDK.S3.abort_multipart_upload("uploads-bucket", "big.bin", upload_id)
      #=> {:ok, %{}}

  Frees the parts already uploaded. Safe to call after a partial failure.
  """
  @spec abort_multipart_upload(
          bucket :: binary(),
          key :: binary(),
          upload_id :: binary(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def abort_multipart_upload(bucket, key, upload_id, opts \\ []) do
    if sandbox?(opts) do
      sandbox_abort_multipart_upload_response(bucket, key, upload_id, opts)
    else
      do_abort_multipart_upload(bucket, key, upload_id, opts)
    end
  end

  @doc """
  Uploads a part of a multipart upload.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:PutObject

  ## Arguments

    * `bucket` - The name of the bucket.
    * `key` - The key of the object.
    * `upload_id` - The upload ID of the multipart upload.
    * `part_number` - The part number (1 to 10,000).
    * `body` - The content of the part (iodata, or an `Enumerable` for streaming).
    * `opts` - A keyword list of options.

  ## Options

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.upload_part("my-bucket", "my-key", "upload-id", 1, "part-data")
      {:ok, %{etag: "...", ...}}

  ## Examples

      AwsSDK.S3.upload_part("uploads-bucket", "big.bin", upload_id, 1, part_body)
      #=> {:ok, %{etag: "\"9a0364b9e99bb480dd25e1f0284c8555\"", part_number: 1}}

  Keep every `:etag` -- `complete_multipart_upload/4` needs the full list.
  Each part must be at least 5 MB except the last.
  """
  @spec upload_part(
          bucket :: binary(),
          key :: binary(),
          upload_id :: binary(),
          part_number :: integer(),
          body :: iodata() | Enumerable.t(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def upload_part(bucket, key, upload_id, part_number, body, opts \\ []) do
    if sandbox?(opts) do
      sandbox_upload_part_response(bucket, key, upload_id, part_number, body, opts)
    else
      do_upload_part(bucket, key, upload_id, part_number, body, opts)
    end
  end

  @doc """
  Returns a list of parts that have been uploaded for a multipart upload.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:ListMultipartUploadParts

  ## Arguments

    * `bucket` - The name of the bucket.
    * `key` - The key of the object.
    * `upload_id` - The upload ID of the multipart upload.
    * `part_number_marker` - Specifies the part after which listing should begin.
    * `opts` - A keyword list of options.

  ## Options

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.list_parts("my-bucket", "my-key", "upload-id")
      {:ok, %{parts: [%{part_number: "1", size: "5242880", etag: "..."}], ...}}

  ## Examples

      AwsSDK.S3.list_parts("uploads-bucket", "big.bin", upload_id)
      #=> {:ok,
      #=>  %{
      #=>    bucket: "uploads-bucket",
      #=>    key: "big.bin",
      #=>    upload_id: "2~kTXQPYyIB8aQ0uQ8sYqLpXQ0nD8fEXAMPLE",
      #=>    max_parts: 1000,
      #=>    is_truncated: false,
      #=>    part_number_marker: nil,
      #=>    next_part_number_marker: nil,
      #=>    storage_class: "STANDARD",
      #=>    initiator: %{id: "abc123...", display_name: "example"},
      #=>    owner: %{id: "abc123...", display_name: "example"},
      #=>    parts: [
      #=>      %{
      #=>        part_number: 1,
      #=>        size: 5_242_880,
      #=>        etag: "\"9a0364b9e99bb480dd25e1f0284c8555\"",
      #=>        last_modified: "2026-01-01T00:00:00.000Z"
      #=>      }
      #=>    ]
      #=>  }}

  Useful for resuming: fetch the parts already stored, then upload only the
  ones missing.
  """
  @spec list_parts(
          bucket :: binary(),
          key :: binary(),
          upload_id :: binary(),
          part_number_marker :: binary() | nil,
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def list_parts(bucket, key, upload_id, part_number_marker \\ nil, opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_parts_response(bucket, key, upload_id, part_number_marker, opts)
    else
      do_list_parts(bucket, key, upload_id, part_number_marker, opts)
    end
  end

  @doc """
  Copies a part from a source object to a destination object as part of a multipart upload.

  ## Permissions

  To execute this request, you must have the following permissions:

    - s3:GetObject (on the source bucket)
    - s3:PutObject (on the destination bucket)

  ## Arguments

    * `dest_bucket` - The name of the destination bucket.
    * `dest_key` - The key for the copied object in the destination bucket.
    * `src_bucket` - The name of the source bucket.
    * `src_key` - The key of the source object.
    * `upload_id` - The upload ID of the multipart upload.
    * `part_number` - The part number for this copy.
    * `src_range` - The byte range to copy from the source (e.g., `0..1048575`).
    * `opts` - A keyword list of options.

  ## Options

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.copy_part("dest-bucket", "dest-key", "src-bucket", "src-key", "upload-id", 1, 0..1048575)
      {:ok, %{etag: "...", last_modified: "..."}}

  ## Examples

      AwsSDK.S3.copy_part(
        "archive-bucket",
        "2026/big.bin",
        upload_id,
        1,
        "uploads-bucket",
        "big.bin",
        range: "bytes=0-5242879"
      )
      #=> {:ok,
      #=>  %{
      #=>    etag: "\"9a0364b9e99bb480dd25e1f0284c8555\"",
      #=>    last_modified: "2026-02-01T00:00:00.000Z"
      #=>  }}

  Copies a byte range server-side, so the data never passes through this
  process.
  """
  @spec copy_part(
          dest_bucket :: binary(),
          dest_key :: binary(),
          src_bucket :: binary(),
          src_key :: binary(),
          upload_id :: binary(),
          part_number :: integer(),
          src_range :: Range.t(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def copy_part(
        dest_bucket,
        dest_key,
        src_bucket,
        src_key,
        upload_id,
        part_number,
        src_range,
        opts
      ) do
    if sandbox?(opts) do
      sandbox_copy_part_response(
        dest_bucket,
        dest_key,
        src_bucket,
        src_key,
        upload_id,
        part_number,
        src_range,
        opts
      )
    else
      do_copy_part(
        dest_bucket,
        dest_key,
        src_bucket,
        src_key,
        upload_id,
        part_number,
        src_range,
        opts
      )
    end
  end

  @doc """
  Copies parts of an object from one location to another using concurrent
  multipart copy operations.

  Partitions the source object into byte-range chunks and copies each
  chunk concurrently using `Task.async_stream/3`.

  ## Permissions

  To execute this request, you must have the following permissions:

    - s3:GetObject (on the source bucket)
    - s3:PutObject (on the destination bucket)

  ## Arguments

    * `dest_bucket` - The name of the destination bucket.
    * `dest_key` - The key for the copied object in the destination bucket.
    * `src_bucket` - The name of the source bucket.
    * `src_key` - The key of the source object.
    * `upload_id` - The upload ID of the multipart upload.
    * `content_length` - The total size of the source object in bytes.
    * `opts` - A keyword list of options.

  ## Options

    * `:content_byte_stream` - A keyword list of byte stream options:
      * `:byte_range_index` - The byte offset to start from. Defaults to 0.
      * `:chunk_size` - The size of each chunk in bytes. Defaults to 64 MiB.
      * `:max_concurrency` - Maximum number of concurrent copy tasks. Defaults to `System.schedulers_online()`.
      * `:timeout` - Timeout per task in milliseconds.
      * `:on_timeout` - What to do on timeout.

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.copy_parts("dest-bucket", "dest-key", "src-bucket", "src-key", "upload-id", 67_108_864)
      {:ok, [{1, "etag1"}, {2, "etag2"}]}

  ## Examples

      AwsSDK.S3.copy_parts(
        "archive-bucket",
        "2026/big.bin",
        upload_id,
        "uploads-bucket",
        "big.bin",
        104_857_600
      )
      #=> {:ok,
      #=>  [
      #=>    %{part_number: 1, etag: "\"9a0364...\""},
      #=>    %{part_number: 2, etag: "\"b1c2d3...\""}
      #=>  ]}

  Splits the source by the given byte size and copies each range. Feed the
  result straight to `complete_multipart_upload/4`.
  """
  @spec copy_parts(
          dest_bucket :: binary(),
          dest_key :: binary(),
          src_bucket :: binary(),
          src_key :: binary(),
          upload_id :: binary(),
          content_length :: integer(),
          opts :: keyword()
        ) :: {:ok, list()} | {:error, list()}
  def copy_parts(
        dest_bucket,
        dest_key,
        src_bucket,
        src_key,
        upload_id,
        content_length,
        opts \\ []
      ) do
    if sandbox?(opts) do
      sandbox_copy_parts_response(
        dest_bucket,
        dest_key,
        src_bucket,
        src_key,
        upload_id,
        content_length,
        opts
      )
    else
      do_copy_parts(
        dest_bucket,
        dest_key,
        src_bucket,
        src_key,
        upload_id,
        content_length,
        opts
      )
    end
  end

  @doc """
  Copies an object from one location to another using multipart upload.

  Orchestrates a full multipart copy workflow: retrieves the source object's
  metadata, initiates a multipart upload, copies all parts concurrently,
  and completes the multipart upload.

  ## Permissions

  To execute this request, you must have the following permissions:

    - s3:GetObject (on the source bucket)
    - s3:PutObject (on the destination bucket)
    - s3:ListMultipartUploadParts (on the destination bucket, required for size validation)

  ## Arguments

    * `dest_bucket` - The name of the destination bucket.
    * `dest_key` - The key for the copied object in the destination bucket.
    * `src_bucket` - The name of the source bucket.
    * `src_key` - The key of the source object.
    * `opts` - A keyword list of options.

  ## Options

  See `copy_parts/7` for byte stream options.
  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.copy_object_multipart("dest-bucket", "dest-key", "src-bucket", "src-key")
      {:ok, %{location: "...", bucket: "dest-bucket", key: "dest-key", etag: "..."}}

  ## Examples

      AwsSDK.S3.copy_object_multipart("archive-bucket", "2026/big.bin", "uploads-bucket", "big.bin")
      #=> {:ok,
      #=>  %{
      #=>    location: "https://archive-bucket.s3.us-east-1.amazonaws.com/2026/big.bin",
      #=>    bucket: "archive-bucket",
      #=>    key: "2026/big.bin",
      #=>    etag: "\"9a0364b9e99bb480dd25e1f0284c8555-2\""
      #=>  }}

  Runs the whole create/copy-parts/complete cycle, aborting the upload if
  any part fails. Use this for objects over 5 GB, which `copy_object/5`
  cannot handle. The trailing `-2` on the ETag is the part count.
  """
  @spec copy_object_multipart(
          dest_bucket :: binary(),
          dest_key :: binary(),
          src_bucket :: binary(),
          src_key :: binary(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def copy_object_multipart(dest_bucket, dest_key, src_bucket, src_key, opts \\ []) do
    do_copy_object_multipart(dest_bucket, dest_key, src_bucket, src_key, opts)
  end

  @doc """
  Completes a multipart upload by assembling previously uploaded parts.

  Optionally validates the total upload size against a maximum and checks the
  content type of the completed object.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:PutObject

  The following permissions may also be required depending on options:

    - s3:ListMultipartUploadParts (required when `:max_size` validation is opted into)
    - s3:GetObject (required when `:content_type` validation is enabled)
    - s3:DeleteObject (required when `:on_content_type_mismatch` is set to `:delete`)

  ## Arguments

    * `bucket` - The name of the bucket.
    * `key` - The key of the object.
    * `upload_id` - The upload ID of the multipart upload.
    * `parts` - A list of `{part_number, etag}` tuples.
    * `opts` - A keyword list of options.

  ## Options

    * `:max_size` - Maximum allowed total size in bytes. Defaults to `:infinity`,
      i.e. size validation is off unless you opt in. `false` and `nil` also
      disable it.

    * `:content_type` - Expected content type of the completed object. Set to `:any` to skip
      content type validation.

    * `:on_content_type_mismatch` - Action to take when content type doesn't match.
      `:error` (default) returns an error without deleting; `:delete` also deletes the object.

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.complete_multipart_upload("my-bucket", "my-key", "upload-id", [{1, "etag1"}, {2, "etag2"}])
      {:ok, %{location: "...", bucket: "my-bucket", key: "my-key", etag: "..."}}

  ## Examples

      AwsSDK.S3.complete_multipart_upload("uploads-bucket", "big.bin", upload_id, [
        %{part_number: 1, etag: "\"9a0364...\""},
        %{part_number: 2, etag: "\"b1c2d3...\""}
      ])
      #=> {:ok,
      #=>  %{
      #=>    location: "https://uploads-bucket.s3.us-east-1.amazonaws.com/big.bin",
      #=>    bucket: "uploads-bucket",
      #=>    key: "big.bin",
      #=>    etag: "\"9a0364b9e99bb480dd25e1f0284c8555-2\""
      #=>  }}

  Parts must be listed in ascending `:part_number` order. This operation can
  return a 200 whose body is an `<Error>`; that is surfaced as
  `{:error, %ErrorMessage{}}` rather than being reported as success.
  """
  @spec complete_multipart_upload(
          bucket :: binary(),
          key :: binary(),
          upload_id :: binary(),
          parts :: list(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def complete_multipart_upload(bucket, key, upload_id, parts, opts \\ []) do
    if sandbox?(opts) do
      sandbox_complete_multipart_upload_response(bucket, key, upload_id, parts, opts)
    else
      do_complete_multipart_upload(bucket, key, upload_id, parts, opts)
    end
  end

  # S3 EventBridge notification configuration

  @doc """
  Enables EventBridge notifications on an S3 bucket.

  Once enabled, all S3 event types are sent to EventBridge. Filtering is done at
  the EventBridge rule level via event patterns. Existing notification configurations
  (SNS, SQS, Lambda) are preserved.

  Idempotent — returns `{:ok, %{}}` if EventBridge is already enabled.

  ## Examples

      AwsSDK.S3.enable_event_bridge("uploads-bucket")
      #=> {:ok, %{}}

  Required before an EventBridge rule built with
  `AwsSDK.EventBridge.s3_object_created_pattern/1` will match anything.

  This replaces the bucket's entire notification configuration, so any
  existing topic, queue or Lambda notifications are dropped.
  """
  @spec enable_event_bridge(bucket :: binary(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def enable_event_bridge(bucket, opts \\ []) do
    if sandbox?(opts) do
      sandbox_enable_event_bridge_response(bucket, opts)
    else
      do_enable_event_bridge(bucket, opts)
    end
  end

  @doc """
  Disables EventBridge notifications on an S3 bucket.

  Other notification configurations (SNS, SQS, Lambda) are preserved.

  Idempotent — returns `{:ok, %{}}` if EventBridge is not currently enabled.

  ## Examples

      AwsSDK.S3.disable_event_bridge("uploads-bucket")
      #=> {:ok, %{}}

  Writes an empty configuration, so this also clears any topic, queue or
  Lambda notifications on the bucket.
  """
  @spec disable_event_bridge(bucket :: binary(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def disable_event_bridge(bucket, opts \\ []) do
    if sandbox?(opts) do
      sandbox_disable_event_bridge_response(bucket, opts)
    else
      do_disable_event_bridge(bucket, opts)
    end
  end

  @doc """
  Returns the notification configuration for an S3 bucket.

  Mirrors AWS's `NotificationConfiguration`: `:topic_configuration`,
  `:queue_configuration`, and `:cloud_function_configuration` lists, plus
  `:event_bridge_configuration`, which is `%{}` when EventBridge is enabled
  and `nil` when it is not (the element carries no members, so its presence
  is the entire signal).

  ## Examples

      AwsSDK.S3.get_notification_configuration("uploads-bucket")
      #=> {:ok,
      #=>  %{
      #=>    event_bridge_configuration: %{},
      #=>    topic_configuration: [],
      #=>    queue_configuration: [
      #=>      %{
      #=>        id: "uploads-to-sqs",
      #=>        queue: "arn:aws:sqs:us-east-1:123456789012:uploads",
      #=>        event: ["s3:ObjectCreated:*"],
      #=>        filter: %{
      #=>          s3_key: %{filter_rule: [%{name: "prefix", value: "incoming/"}]}
      #=>        }
      #=>      }
      #=>    ],
      #=>    cloud_function_configuration: []
      #=>  }}

  `:event_bridge_configuration` is `%{}` when EventBridge is enabled and
  `nil` when it is not -- the element carries no members, so its presence is
  the entire signal.
  """
  @spec get_notification_configuration(bucket :: binary(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def get_notification_configuration(bucket, opts \\ []) do
    if sandbox?(opts) do
      sandbox_get_notification_configuration_response(bucket, opts)
    else
      do_get_notification_configuration(bucket, opts)
    end
  end

  # S3 bucket configuration

  @doc """
  Sets the public access block configuration for a bucket.

  All four flags default to `true` (the most restrictive setting). Pass
  `false` for any flag you want to relax.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:PutBucketPublicAccessBlock

  ## Arguments

    * `bucket` - The name of the bucket.
    * `opts` - A keyword list of options.

  ## Options

  Only the flags you supply are sent; AWS leaves any omitted flag unchanged.
  Nothing is defaulted, so setting one flag does not disturb the other three.

    * `:block_public_acls` - Reject public ACLs on this bucket and its objects.
    * `:ignore_public_acls` - Ignore public ACLs on this bucket and its objects.
    * `:block_public_policy` - Reject bucket policies that grant public access.
    * `:restrict_public_buckets` - Restrict cross-account access to buckets with public policies.

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.put_public_access_block("my-bucket")
      {:ok, %{x_amz_request_id: "...", date: "..."}}

      iex> AwsSDK.S3.put_public_access_block("my-bucket", block_public_acls: false)
      {:ok, %{x_amz_request_id: "...", date: "..."}}

  ## Examples

      AwsSDK.S3.put_public_access_block("uploads-bucket",
        block_public_acls: true,
        ignore_public_acls: true,
        block_public_policy: true,
        restrict_public_buckets: true
      )
      #=> {:ok, %{}}

  Only the flags you pass are sent; omitted flags are left at their current
  value rather than being reset to false.
  """
  @spec put_public_access_block(bucket :: binary(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def put_public_access_block(bucket, opts \\ []) do
    if sandbox?(opts) do
      sandbox_put_public_access_block_response(bucket, opts)
    else
      do_put_public_access_block(bucket, opts)
    end
  end

  @doc """
  Sets the default server-side encryption configuration for a bucket.

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:PutEncryptionConfiguration

  ## Arguments

    * `bucket` - The name of the bucket.
    * `opts` - A keyword list of options.

  ## Options

    * `:sse_algorithm` - The server-side encryption algorithm. One of `"AES256"` (default),
      `"aws:kms"`, or `"aws:kms:dsse"`.
    * `:kms_master_key_id` - The KMS key ID or ARN to use for encryption. Required when
      `:sse_algorithm` is a KMS variant.
    * `:bucket_key_enabled` - Whether to enable S3 Bucket Keys to reduce KMS request costs.

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.put_bucket_encryption("my-bucket")
      {:ok, %{x_amz_request_id: "...", date: "..."}}

      iex> AwsSDK.S3.put_bucket_encryption("my-bucket",
      ...>   sse_algorithm: "aws:kms",
      ...>   kms_master_key_id: "arn:aws:kms:us-east-1:111122223333:key/abcd",
      ...>   bucket_key_enabled: true
      ...> )
      {:ok, %{x_amz_request_id: "...", date: "..."}}

  ## Examples

      AwsSDK.S3.put_bucket_encryption("uploads-bucket")
      #=> {:ok, %{}}

      AwsSDK.S3.put_bucket_encryption("uploads-bucket",
        sse_algorithm: "aws:kms",
        kms_master_key_id: "arn:aws:kms:us-east-1:123456789012:key/abc",
        bucket_key_enabled: true
      )
      #=> {:ok, %{}}

  Defaults to `"AES256"` when no algorithm is given.
  """
  @spec put_bucket_encryption(bucket :: binary(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def put_bucket_encryption(bucket, opts \\ []) do
    if sandbox?(opts) do
      sandbox_put_bucket_encryption_response(bucket, opts)
    else
      do_put_bucket_encryption(bucket, opts)
    end
  end

  @doc """
  Sets the lifecycle configuration for a bucket.

  Replaces any existing lifecycle configuration. Pass an empty list to clear all rules
  (note that AWS requires at least one rule, so to remove the configuration entirely
  use the DELETE Bucket lifecycle API instead).

  ## Permissions

  To execute this request, you must have the following permission:

    - s3:PutLifecycleConfiguration

  ## Arguments

    * `bucket` - The name of the bucket.
    * `rules` - A list of rule maps. Each rule supports the following keys:

      * `:id` - Required. A unique identifier for the rule (max 255 characters).
      * `:status` - `"Enabled"` (default) or `"Disabled"`.
      * `:filter` - A map describing which objects the rule applies to. Common shapes:
        * `%{prefix: "logs/"}` - prefix-only filter
        * `%{}` - empty filter (applies to all objects)
        * `%{object_size_greater_than: 1024}` / `%{object_size_less_than: 1_000_000}`
        * `%{tag: %{key: "k", value: "v"}}` - single tag
        Defaults to an empty filter.
      * `:expiration` - A map. Examples: `%{days: 30}`, `%{date: "2026-01-01T00:00:00Z"}`,
        `%{expired_object_delete_marker: true}`.
      * `:transitions` - A list of `%{days: N, storage_class: "GLACIER"}` (or `:date`).
      * `:noncurrent_version_expiration` - `%{noncurrent_days: N}`.
      * `:noncurrent_version_transitions` - A list of `%{noncurrent_days: N, storage_class: "..."}`.
      * `:abort_incomplete_multipart_upload` - `%{days_after_initiation: N}`.

    * `opts` - A keyword list of options.

  ## Options

  See the "Shared Options" section in the module documentation for common options.

  ## Examples

      iex> AwsSDK.S3.put_bucket_lifecycle_configuration("my-bucket", [
      ...>   %{id: "expire-logs", filter: %{prefix: "logs/"}, expiration: %{days: 30}}
      ...> ])
      {:ok, %{x_amz_request_id: "...", date: "..."}}

  ## Examples

      AwsSDK.S3.put_bucket_lifecycle_configuration("uploads-bucket", [
        %{
          id: "expire-incoming",
          status: "Enabled",
          filter: %{prefix: "incoming/"},
          expiration: %{days: 30}
        },
        %{
          id: "archive-reports",
          filter: %{prefix: "reports/"},
          transitions: [%{days: 90, storage_class: "GLACIER"}]
        }
      ])
      #=> {:ok, %{}}

  Replaces the whole configuration. A rule with no `:status` defaults to
  `"Enabled"`.
  """
  @spec put_bucket_lifecycle_configuration(
          bucket :: binary(),
          rules :: list(map()),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def put_bucket_lifecycle_configuration(bucket, rules, opts \\ []) when is_list(rules) do
    if sandbox?(opts) do
      sandbox_put_bucket_lifecycle_configuration_response(bucket, rules, opts)
    else
      do_put_bucket_lifecycle_configuration(bucket, rules, opts)
    end
  end

  @doc false
  def build_operation(method, bucket, key, opts) do
    with {:ok, config} <- resolve_config(opts) do
      user_headers = Keyword.get(opts, :headers, [])
      query = Keyword.get(opts, :query, %{})
      body = Keyword.get(opts, :body, "")
      stream_response? = Keyword.get(opts, :stream_response, false)

      url = build_url(config, bucket, key, query)
      {payload_hash, stream_upload?} = classify_body(body)

      op = %Operation{
        method: method,
        url: url,
        headers: user_headers,
        body: body,
        service: @service,
        region: config.region,
        access_key_id: config.access_key_id,
        secret_access_key: config.secret_access_key,
        security_token: config.security_token,
        payload_hash: payload_hash,
        stream_upload: stream_upload?,
        stream_response: stream_response?,
        http: Keyword.get(opts, :http, [])
      }

      {:ok, apply_overrides(op, opts[:s3] || [])}
    end
  end

  @doc """
  Returns the URL a caller would hit for `{bucket, key, query}` given
  `opts`. Used by presigning so the SigV4 signature lines up with the
  URL built by `build_operation/4`.

  ## Examples

      {:ok, config} = AwsSDK.S3.resolve_config(region: "us-east-1")

      AwsSDK.S3.build_url(config, "uploads", "reports/jan.csv", %{})
      #=> "https://uploads.s3.us-east-1.amazonaws.com/reports/jan.csv"

      # Reserved characters are percent-encoded with AWS's UriEncode rules,
      # so the signer can sign the path verbatim and still match the wire.
      AwsSDK.S3.build_url(config, "uploads", "my file+a:b#c.txt", %{"versionId" => "abc"})
      #=> "https://uploads.s3.us-east-1.amazonaws.com/my%20file%2Ba%3Ab%23c.txt?versionId=abc"
  """
  @spec build_url(keyword | map, binary | nil, binary | nil, map | keyword) :: String.t()
  def build_url(opts, bucket, key, query) when is_list(opts) do
    case resolve_config(opts) do
      {:ok, config} -> build_url(config, bucket, key, query)
      {:error, reason} -> raise ArgumentError, "cannot build S3 URL: #{inspect(reason)}"
    end
  end

  def build_url(config, bucket, key, query) when is_map(config) do
    {host, path_prefix} = address(config, bucket)
    base_path = build_base_path(path_prefix, key)
    port_part = port_suffix(config.scheme, config.port)
    query_part = build_query_part(query)

    "#{config.scheme}://#{host}#{port_part}#{base_path}#{query_part}"
  end

  @doc """
  Resolves the full config map (region, scheme, host, port, creds,
  path_style) for a given opts keyword. Exposed so presigners can reuse it.

  ## Examples

      AwsSDK.S3.resolve_config(access_key_id: "AK", secret_access_key: "SK", region: "us-east-1")
      #=> {:ok,
      #=>  %{
      #=>    scheme: "https",
      #=>    host: "s3.us-east-1.amazonaws.com",
      #=>    port: nil,
      #=>    region: "us-east-1",
      #=>    access_key_id: "AK",
      #=>    secret_access_key: "SK",
      #=>    security_token: nil,
      #=>    path_style: false
      #=>  }}

  Adds `:path_style` to the shared config shape, since S3 is the only
  service here that has to choose between virtual-hosted and path
  addressing.
  """
  @spec resolve_config(keyword) :: {:ok, map} | {:error, term}
  def resolve_config(opts) do
    {sandbox_opts, _} = Keyword.pop(opts, :sandbox, [])

    with {:ok, config} <-
           Client.resolve_config(:s3, opts, &"s3.#{&1}.amazonaws.com", [:path_style]) do
      path_style = resolve_path_style(config.path_style, sandbox_opts)
      {:ok, Map.put(config, :path_style, path_style)}
    end
  end

  defp do_list_buckets(opts) do
    query =
      %{}
      |> maybe_put_query("prefix", opts[:prefix])
      |> maybe_put_query("max-buckets", opts[:max_buckets])
      |> maybe_put_query("continuation-token", opts[:continuation_token])
      |> maybe_put_query("bucket-region", opts[:bucket_region])

    with {:ok, op} <- build_operation(:get, nil, nil, Keyword.put(opts, :query, query)),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, XMLParser.parse_list_buckets(body)}
    end
  end

  defp do_create_bucket(bucket, opts) do
    region = opts[:region] || Config.region() || "us-east-1"
    body = create_bucket_body(region)

    with {:ok, op} <- build_operation(:put, bucket, nil, Keyword.put(opts, :body, body)) do
      case Client.request(op) do
        {:error, %ErrorMessage{details: %{status: 409, response: resp}}} ->
          {:error,
           ErrorMessage.conflict(
             "bucket already exists",
             %{bucket: bucket, region: region, response: resp}
           )}

        {:ok, %{headers: headers}} ->
          {:ok, deserialize_headers(headers, opts)}

        {:error, _} = error ->
          error
      end
    end
  end

  defp create_bucket_body("us-east-1"), do: ""

  defp create_bucket_body(region) do
    "<CreateBucketConfiguration><LocationConstraint>#{region}</LocationConstraint></CreateBucketConfiguration>"
  end

  defp do_delete_bucket(bucket, opts) do
    with {:ok, op} <- build_operation(:delete, bucket, nil, opts),
         {:ok, %{headers: headers}} <- Client.request(op) do
      {:ok, deserialize_headers(headers, opts)}
    end
  end

  defp do_head_bucket(bucket, opts) do
    with {:ok, op} <- build_operation(:head, bucket, nil, opts),
         {:ok, %{headers: headers}} <- Client.request(op) do
      {:ok, deserialize_headers(headers, opts)}
    end
  end

  defp do_put_object(bucket, key, body, opts) do
    headers = opts |> object_headers() |> maybe_add_if_none_match(opts)
    if_none_match? = Keyword.get(opts, :if_none_match, false)

    with {:ok, op} <-
           build_operation(:put, bucket, key, put_opts(opts, body: body, headers: headers)) do
      case Client.request(op) do
        {:error, %ErrorMessage{details: %{status: 412, response: resp}}} when if_none_match? ->
          {:error,
           ErrorMessage.conflict(
             "object already exists",
             %{bucket: bucket, key: key, response: resp}
           )}

        {:ok, %{headers: headers}} ->
          {:ok, deserialize_headers(headers, opts)}

        {:error, _} = error ->
          error
      end
    end
  end

  defp do_head_object(bucket, key, opts) do
    with {:ok, op} <- build_operation(:head, bucket, key, opts),
         {:ok, %{headers: headers}} <- Client.request(op) do
      {:ok, deserialize_headers(headers, opts)}
    end
  end

  defp do_delete_object(bucket, key, opts) do
    with {:ok, op} <- build_operation(:delete, bucket, key, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, body}
    end
  end

  defp do_delete_objects(bucket, objects, opts) do
    xml = XMLBuilder.build_delete(objects, opts[:quiet] || false)
    headers = xml_body_headers(xml)
    request_opts = put_opts(opts, query: %{"delete" => ""}, body: xml, headers: headers)

    # S3 requires Content-MD5 on DeleteObjects; xml_body_headers/1 supplies it.
    with {:ok, op} <- build_operation(:post, bucket, nil, request_opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, XMLParser.parse_delete_result(body)}
    end
  end

  defp do_get_object(bucket, key, opts) do
    decode_json? = Keyword.get(opts, :decode_json, false)

    with {:ok, op} <- build_operation(:get, bucket, key, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, if(decode_json?, do: Jason.decode!(body), else: body)}
    end
  end

  defp do_list_objects(bucket, opts) do
    query = list_objects_query(opts)

    # Returning only `:contents` discarded `is_truncated` and
    # `next_continuation_token`, so a caller silently received at most one
    # page with no way to tell there were more.
    with {:ok, op} <- build_operation(:get, bucket, nil, Keyword.put(opts, :query, query)),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, XMLParser.parse_list_objects(body)}
    end
  end

  defp list_objects_query(opts) do
    %{"list-type" => "2"}
    |> maybe_put_query("prefix", opts[:prefix])
    |> maybe_put_query("delimiter", opts[:delimiter])
    |> maybe_put_query("max-keys", opts[:max_keys])
    |> maybe_put_query("start-after", opts[:start_after])
    |> maybe_put_query("continuation-token", opts[:continuation_token])
    |> maybe_put_query("fetch-owner", opts[:fetch_owner])
    |> maybe_put_query("encoding-type", opts[:encoding_type])
  end

  defp do_copy_object(dest_bucket, dest_key, src_bucket, src_key, opts) do
    headers = [{"x-amz-copy-source", copy_source(src_bucket, src_key)}]

    with {:ok, op} <-
           build_operation(
             :put,
             dest_bucket,
             dest_key,
             put_opts(opts, body: "", headers: headers)
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      case XMLParser.parse_copy_object_result(body) do
        {:error, _} = error -> error
        result -> {:ok, result}
      end
    end
  end

  defp do_presign(bucket, http_method, key, opts) do
    expires_in = opts[:expires_in] || @sixty_seconds
    {:ok, config} = resolve_config(opts)
    query_params = Map.new(opts[:query_params] || %{})
    url = build_url(config, bucket, key, query_params)

    signed_url = Signer.sign_query(http_method, url, [], expires_in, signer_creds(config))

    %{
      key: key,
      url: signed_url,
      expires_in: expires_in,
      expires_at: DateTime.add(DateTime.utc_now(), expires_in, :second)
    }
  end

  defp do_presign_post(bucket, key, opts) do
    expires_in = opts[:expires_in] || @sixty_seconds
    min_size = Keyword.get(opts, :min_size, 0)
    max_size = Keyword.get(opts, :max_size, @one_gib)

    {:ok, config} = resolve_config(opts)
    url = build_url(config, bucket, nil, %{})

    conditions =
      maybe_add_content_type_condition(
        [
          %{"bucket" => bucket},
          %{"key" => key},
          ["content-length-range", min_size, max_size]
        ],
        opts[:content_type]
      )

    result = Signer.presign_post_policy(url, conditions, expires_in, signer_creds(config))

    # These are literal HTML form field names that S3 matches byte-for-byte
    # ("policy", "x-amz-algorithm", "x-amz-credential", "x-amz-date",
    # "x-amz-signature", "x-amz-security-token"). Running them through the
    # response deserializer snake-cased them into atoms like
    # `:x_amz_algorithm`, and a form built from those is rejected.
    fields = Map.put(result.fields, "key", key)

    {:ok,
     %{
       fields: fields,
       url: result.url,
       expires_in: expires_in,
       expires_at: DateTime.add(DateTime.utc_now(), expires_in, :second)
     }}
  end

  defp maybe_add_content_type_condition(conditions, nil), do: conditions

  defp maybe_add_content_type_condition(conditions, content_type) do
    conditions ++ [["starts-with", "$Content-Type", content_type]]
  end

  defp do_presign_part(bucket, object, upload_id, part_number, opts) do
    query_params = %{"uploadId" => upload_id, "partNumber" => to_string(part_number)}
    opts = Keyword.update(opts, :query_params, query_params, &Map.merge(&1, query_params))
    presign(bucket, :put, object, opts)
  end

  defp do_create_multipart_upload(bucket, key, opts) do
    expires = resolve_expires(opts[:expires])
    headers = object_headers(opts) ++ maybe_expires_header(expires)

    with {:ok, op} <-
           build_operation(
             :post,
             bucket,
             key,
             put_opts(opts, query: %{"uploads" => ""}, body: "", headers: headers)
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, XMLParser.parse_initiate_multipart(body)}
    end
  end

  # `Expires` is object cache-expiry metadata and is optional to AWS; send
  # it only when the caller asks for it.
  defp resolve_expires(nil), do: nil
  defp resolve_expires(%DateTime{} = datetime), do: to_http_date(datetime)
  defp resolve_expires(expires) when is_binary(expires), do: expires

  defp maybe_expires_header(nil), do: []

  defp maybe_expires_header(expires) when is_binary(expires) do
    [{"expires", expires}]
  end

  defp do_abort_multipart_upload(bucket, key, upload_id, opts) do
    with {:ok, op} <-
           build_operation(
             :delete,
             bucket,
             key,
             Keyword.put(opts, :query, %{"uploadId" => upload_id})
           ),
         {:ok, %{headers: headers}} <- Client.request(op) do
      {:ok, deserialize_headers(headers, opts)}
    end
  end

  defp do_upload_part(bucket, key, upload_id, part_number, body, opts) do
    query = %{"uploadId" => upload_id, "partNumber" => to_string(part_number)}

    with {:ok, op} <- build_operation(:put, bucket, key, put_opts(opts, query: query, body: body)),
         {:ok, %{headers: headers}} <- Client.request(op) do
      {:ok, deserialize_headers(headers, opts)}
    end
  end

  defp do_list_parts(bucket, key, upload_id, part_number_marker, opts) do
    query = maybe_put_query(%{"uploadId" => upload_id}, "part-number-marker", part_number_marker)

    with {:ok, op} <- build_operation(:get, bucket, key, Keyword.put(opts, :query, query)),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, XMLParser.parse_list_parts(body)}
    end
  end

  defp do_copy_part(
         dest_bucket,
         dest_key,
         src_bucket,
         src_key,
         upload_id,
         part_number,
         src_range,
         opts
       ) do
    query = %{"uploadId" => upload_id, "partNumber" => to_string(part_number)}

    headers = [
      {"x-amz-copy-source", copy_source(src_bucket, src_key)},
      {"x-amz-copy-source-range", range_header(src_range)}
    ]

    with {:ok, op} <-
           build_operation(
             :put,
             dest_bucket,
             dest_key,
             put_opts(opts, query: query, body: "", headers: headers)
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, XMLParser.parse_copy_part(body)}
    end
  end

  defp do_copy_parts(
         dest_bucket,
         dest_key,
         src_bucket,
         src_key,
         upload_id,
         content_length,
         opts
       ) do
    content_byte_stream_opts = opts[:content_byte_stream] || []
    content_byte_range_index = content_byte_stream_opts[:byte_range_index] || 0
    content_chunk_size = content_byte_stream_opts[:chunk_size] || @sixty_four_mib

    async_stream_opts =
      content_byte_stream_opts
      |> Keyword.take([:max_concurrency, :timeout, :on_timeout])
      |> Keyword.put_new(:max_concurrency, System.schedulers_online())
      |> Keyword.put(:ordered, false)

    content_byte_range_index
    |> Multipart.content_byte_stream(content_length, content_chunk_size)
    |> Stream.with_index(1)
    |> Task.async_stream(
      fn {{start_byte, end_byte}, part_num} ->
        copy_part_range(
          dest_bucket,
          dest_key,
          src_bucket,
          src_key,
          upload_id,
          part_num,
          {start_byte, end_byte, content_length},
          opts
        )
      end,
      async_stream_opts
    )
    |> handle_async_stream_response()
  end

  defp do_copy_object_multipart(dest_bucket, dest_key, src_bucket, src_key, opts) do
    with {:ok, info} <- head_object(src_bucket, src_key, opts),
         {:ok, mpu} <- create_multipart_upload(dest_bucket, dest_key, opts) do
      content_length = String.to_integer(info.content_length)

      result =
        copy_and_complete(
          dest_bucket,
          dest_key,
          src_bucket,
          src_key,
          mpu.upload_id,
          content_length,
          opts
        )

      with {:error, _} = copy_error <- result do
        abort_after_failed_copy(copy_error, dest_bucket, dest_key, mpu.upload_id, opts)
      end
    end
  end

  # This function creates the upload, so on failure the caller never learns
  # the upload id and cannot abort it themselves.
  defp abort_after_failed_copy(copy_error, bucket, key, upload_id, opts) do
    case abort_multipart_upload(bucket, key, upload_id, opts) do
      # Cleaned up. Report why the copy failed.
      {:ok, _} -> copy_error
      # Not cleaned up: an upload is left billing. That outranks the copy.
      {:error, _} = abort_error -> abort_error
    end
  end

  defp copy_and_complete(
         dest_bucket,
         dest_key,
         src_bucket,
         src_key,
         upload_id,
         content_length,
         opts
       ) do
    with {:ok, parts} <-
           copy_parts(
             dest_bucket,
             dest_key,
             src_bucket,
             src_key,
             upload_id,
             content_length,
             opts
           ) do
      parts
      |> Enum.map(fn {%{etag: etag}, part_num} -> {part_num, etag} end)
      |> Enum.sort()
      |> then(&complete_multipart_upload(dest_bucket, dest_key, upload_id, &1, opts))
    end
  end

  defp do_complete_multipart_upload(bucket, key, upload_id, parts, opts) do
    with :ok <- validate_multipart_size(bucket, key, upload_id, opts) do
      xml = build_complete_multipart_xml(validate_parts!(parts))
      query = %{"uploadId" => upload_id}
      headers = [{"content-type", "application/xml"}]

      with {:ok, op} <-
             build_operation(
               :post,
               bucket,
               key,
               put_opts(opts, query: query, body: xml, headers: headers)
             ),
           {:ok, response} <- Client.request(op) do
        case deserialize_completed_multipart(response, bucket, key, upload_id, opts) do
          {:error, _} = error -> error
          result -> {:ok, result}
        end
      end
    end
  end

  defp deserialize_completed_multipart(%{body: body}, bucket, key, upload_id, opts) do
    with :ok <- validate_multipart_content_type(bucket, key, upload_id, opts) do
      XMLParser.parse_complete_multipart(body)
    end
  end

  defp build_complete_multipart_xml(parts) do
    parts_xml =
      Enum.map_join(parts, "", fn {num, etag} ->
        "<Part><PartNumber>#{num}</PartNumber><ETag>#{etag}</ETag></Part>"
      end)

    "<CompleteMultipartUpload>#{parts_xml}</CompleteMultipartUpload>"
  end

  defp do_enable_event_bridge(bucket, opts) do
    with {:ok, xml} <- get_raw_notification_xml(bucket, opts) do
      if String.contains?(xml, "EventBridgeConfiguration") do
        {:ok, %{}}
      else
        xml = expand_self_closing_notification(xml)
        new_xml = insert_event_bridge_config(xml)
        put_notification_xml(bucket, new_xml, opts)
      end
    end
  end

  defp do_disable_event_bridge(bucket, opts) do
    with {:ok, xml} <- get_raw_notification_xml(bucket, opts) do
      if String.contains?(xml, "EventBridgeConfiguration") do
        new_xml = remove_event_bridge_config(xml)
        put_notification_xml(bucket, new_xml, opts)
      else
        {:ok, %{}}
      end
    end
  end

  defp do_get_notification_configuration(bucket, opts) do
    with {:ok, xml} <- get_raw_notification_xml(bucket, opts) do
      {:ok, XMLParser.parse_notification_configuration(xml)}
    end
  end

  defp get_raw_notification_xml(bucket, opts) do
    with {:ok, op} <-
           build_operation(:get, bucket, nil, Keyword.put(opts, :query, %{"notification" => ""})),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, body}
    end
  end

  defp put_notification_xml(bucket, xml, opts) do
    md5 = :md5 |> :crypto.hash(xml) |> Base.encode64()

    headers = [
      {"content-md5", md5},
      {"content-type", "application/xml"}
    ]

    with {:ok, op} <-
           build_operation(
             :put,
             bucket,
             nil,
             put_opts(opts, query: %{"notification" => ""}, body: xml, headers: headers)
           ),
         {:ok, _} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  defp insert_event_bridge_config(xml) do
    String.replace(
      xml,
      "</NotificationConfiguration>",
      "<EventBridgeConfiguration/></NotificationConfiguration>"
    )
  end

  defp remove_event_bridge_config(xml) do
    String.replace(
      xml,
      ~r/<EventBridgeConfiguration\s*\/?>(\s*<\/EventBridgeConfiguration>)?/,
      ""
    )
  end

  defp expand_self_closing_notification(xml) do
    String.replace(
      xml,
      ~r/<NotificationConfiguration\s*\/>/,
      "<NotificationConfiguration></NotificationConfiguration>"
    )
  end

  defp do_put_public_access_block(bucket, opts) do
    xml = XMLBuilder.build_public_access_block(opts)
    put_bucket_config(bucket, "publicAccessBlock", xml, opts)
  end

  defp do_put_bucket_encryption(bucket, opts) do
    xml = XMLBuilder.build_bucket_encryption(opts)
    put_bucket_config(bucket, "encryption", xml, opts)
  end

  defp do_put_bucket_lifecycle_configuration(bucket, rules, opts) do
    xml = XMLBuilder.build_lifecycle_configuration(rules)
    put_bucket_config(bucket, "lifecycle", xml, opts)
  end

  defp put_bucket_config(bucket, query_key, xml, opts) do
    headers = xml_body_headers(xml)
    request_opts = put_opts(opts, query: %{query_key => ""}, body: xml, headers: headers)

    with {:ok, op} <- build_operation(:put, bucket, nil, request_opts),
         {:ok, %{headers: response_headers}} <- Client.request(op) do
      {:ok, deserialize_headers(response_headers, opts)}
    end
  end

  defp xml_body_headers(xml) do
    md5 = :md5 |> :crypto.hash(xml) |> Base.encode64()
    [{"content-md5", md5}, {"content-type", "application/xml"}]
  end

  # AWS owns the response-header namespace and adds new headers over time
  # (e.g. `x-amz-checksum-crc64nvme`). `Serializer.deserialize/2`'s default
  # is `to_existing_atom: true, strict: true`, which crashes on any header
  # whose snake-cased atom hasn't been referenced elsewhere. Headers must
  # round-trip without crashing, so atom-safety is relaxed here by default.
  # Callers can still override any of these options by passing their own
  # `opts` -- caller-supplied keys win the merge.
  @response_header_opts [to_existing_atom: false, strict: false]

  defp deserialize_headers(headers, opts) do
    headers
    |> Serializer.deserialize(merge_response_header_opts(opts))
    |> Map.new()
  end

  defp merge_response_header_opts(opts), do: Keyword.merge(@response_header_opts, opts)

  defp copy_part_range(
         dest_bucket,
         dest_key,
         src_bucket,
         src_key,
         upload_id,
         part_num,
         {start_byte, end_byte, _content_length},
         opts
       ) do
    case copy_part(
           dest_bucket,
           dest_key,
           src_bucket,
           src_key,
           upload_id,
           part_num,
           Range.new(start_byte, end_byte),
           opts
         ) do
      {:ok, result} -> {:ok, {result, part_num}}
      {:error, term} -> {:error, {term, part_num}}
    end
  end

  defp handle_async_stream_response(results) do
    results
    |> Enum.reduce({[], []}, fn
      {:ok, {:ok, result}}, {results, errors} ->
        {[result | results], errors}

      {:ok, {:error, reason}}, {results, errors} ->
        {results, [reason | errors]}

      {:exit, reason}, {results, errors} ->
        err = ErrorMessage.internal_server_error("task exited", %{reason: reason})
        {results, [err | errors]}
    end)
    |> then(fn
      {results, []} -> {:ok, Enum.reverse(results)}
      {_, errors} -> {:error, Enum.reverse(errors)}
    end)
  end

  # AWS enforces its own 5 TiB limit, so no check runs unless the caller
  # asks for one. Exceeding an opted-in `:max_size` reports the error; the
  # caller decides whether to abort.
  defp validate_multipart_size(bucket, key, upload_id, opts) do
    case Keyword.get(opts, :max_size, :infinity) do
      :infinity -> :ok
      false -> :ok
      nil -> :ok
      max -> check_multipart_size(bucket, key, upload_id, max, opts)
    end
  end

  defp check_multipart_size(bucket, key, upload_id, max, opts) do
    with {:ok, size} <- aggregate_object_size(bucket, key, upload_id, opts) do
      if size > max do
        {:error,
         ErrorMessage.forbidden(
           "multipart upload size exceeds maximum allowed size",
           %{
             bucket: bucket,
             key: key,
             upload_id: upload_id,
             max_size: max,
             size: size
           }
         )}
      else
        :ok
      end
    end
  end

  defp aggregate_object_size(bucket, key, upload_id, opts) do
    do_aggregate_object_size(bucket, key, upload_id, nil, 0, opts)
  end

  defp do_aggregate_object_size(bucket, key, upload_id, part_number_marker, acc, opts) do
    case list_parts(bucket, key, upload_id, part_number_marker, opts) do
      {:ok, %{parts: parts} = body} ->
        size = Enum.reduce(parts, 0, fn p, sum -> sum + part_size(p.size) end)
        acc2 = acc + size

        if body.is_truncated do
          do_aggregate_object_size(
            bucket,
            key,
            upload_id,
            body.next_part_number_marker,
            acc2,
            opts
          )
        else
          {:ok, acc2}
        end

      {:error, _} = error ->
        error
    end
  end

  defp part_size(nil), do: 0
  defp part_size(size) when is_integer(size), do: size
  defp part_size(size) when is_binary(size) and size !== "", do: String.to_integer(size)
  defp part_size(_), do: 0

  defp validate_multipart_content_type(bucket, key, upload_id, opts) do
    case Keyword.get(opts, :content_type) do
      nil -> :ok
      :any -> :ok
      content_type -> check_content_type(bucket, key, upload_id, content_type, opts)
    end
  end

  defp check_content_type(bucket, key, upload_id, content_type, opts) do
    with {:ok, meta} <- head_object(bucket, key, opts) do
      if content_type_match?(content_type, meta.content_type) do
        :ok
      else
        handle_content_type_mismatch(bucket, key, upload_id, content_type, opts)
      end
    end
  end

  defp handle_content_type_mismatch(bucket, key, upload_id, content_type, opts) do
    error =
      {:error,
       ErrorMessage.forbidden(
         "content type mismatch",
         %{
           bucket: bucket,
           key: key,
           upload_id: upload_id,
           content_type: content_type
         }
       )}

    # Reporting is the default: the upload succeeded, and deleting the
    # caller's object is unrecoverable on an unversioned bucket.
    case Keyword.get(opts, :on_content_type_mismatch, :error) do
      :delete -> with {:ok, _} <- delete_object(bucket, key, opts), do: error
      :error -> error
    end
  end

  defp content_type_match?(expected, actual) when is_struct(expected, Regex) do
    Regex.match?(expected, actual)
  end

  # `a =~ b` on two binaries is `String.contains?(a, b)`. The arguments were
  # the wrong way round, so an expected prefix of "image/" against an actual
  # "image/png" reported a mismatch -- and with
  # `on_content_type_mismatch: :delete` that deleted the object.
  defp content_type_match?(expected, actual) when is_binary(expected) do
    actual =~ expected
  end

  defp validate_parts!(entries) do
    Enum.map(entries, fn
      {part, etag} when is_integer(part) and is_binary(etag) ->
        {part, etag}

      {part, etag} when is_binary(part) and is_binary(etag) ->
        {String.to_integer(part), etag}

      failed_value ->
        raise ArgumentError, """
        Expected parts parameters to be a list of `{part_number :: integer(), etag :: binary()}`

        failed_value:

        #{inspect(failed_value)}

        entries:

        #{inspect(entries)}
        """
    end)
  end

  defp to_http_date(datetime) do
    datetime
    |> DateTime.to_unix(:second)
    |> DateTime.from_unix!()
    |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
  end

  # --- Opt / header helpers --------------------------------------------------

  # Merge caller opts with per-operation keys; per-op values win (the most
  # recent call to `put_opts` decides).
  defp put_opts(opts, extra), do: Keyword.merge(opts, extra)

  defp maybe_put_query(query, _key, nil), do: query
  defp maybe_put_query(query, _key, ""), do: query
  defp maybe_put_query(query, key, value), do: Map.put(query, key, to_string(value))

  defp object_headers(opts) do
    explicit = Keyword.get(opts, :headers, [])

    explicit
    |> maybe_add_header("content-type", opts[:content_type])
    |> maybe_add_header("x-amz-acl", opts[:acl])
  end

  defp maybe_add_header(headers, _key, nil), do: headers
  defp maybe_add_header(headers, key, value), do: [{key, to_string(value)} | headers]

  defp maybe_add_if_none_match(headers, opts) do
    cond do
      not Keyword.get(opts, :if_none_match, false) -> headers
      List.keymember?(headers, "if-none-match", 0) -> headers
      true -> headers ++ [{"if-none-match", Keyword.get(opts, :if_none_match_pattern, "*")}]
    end
  end

  # CopyObject and UploadPartCopy both document this value as URL-encoded. An
  # unencoded key breaks in three ways: a `?` is read as the start of
  # `versionId`, a space or non-ASCII 404s, and because `x-amz-copy-source` is
  # a signed header the signature no longer matches what is sent.
  defp copy_source(src_bucket, src_key) do
    "/" <> src_bucket <> "/" <> encode_key(src_key)
  end

  defp range_header(first..last//_step) do
    "bytes=#{first}-#{last}"
  end

  defp signer_creds(config) do
    %{
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      token: config.security_token,
      region: config.region,
      service: @service,
      now: DateTime.utc_now()
    }
  end

  # ---------------------------------------------------------------------------
  # PRIVATE HELPERS
  # ---------------------------------------------------------------------------

  defp build_base_path(nil, nil), do: "/"
  defp build_base_path(nil, key), do: "/" <> encode_key(key)
  defp build_base_path(prefix, nil), do: "/" <> prefix
  defp build_base_path(prefix, key), do: "/" <> prefix <> "/" <> encode_key(key)

  defp port_suffix(_scheme, nil), do: ""
  defp port_suffix("https", 443), do: ""
  defp port_suffix("http", 80), do: ""
  defp port_suffix(_scheme, port), do: ":#{port}"

  defp build_query_part(query) do
    case encode_query(query) do
      "" -> ""
      qs -> "?" <> qs
    end
  end

  defp address(%{path_style: true, host: host}, bucket) do
    case bucket do
      nil -> {host, nil}
      b -> {host, b}
    end
  end

  defp address(%{host: host}, nil), do: {host, nil}
  defp address(%{host: host}, bucket), do: {"#{bucket}.#{host}", nil}

  defp encode_key(key) do
    key
    |> String.split("/")
    |> Enum.map_join("/", fn segment -> URI.encode(segment, &URI.char_unreserved?/1) end)
  end

  defp encode_query(map) when map_size(map) === 0, do: ""

  defp encode_query(map) when is_map(map) or is_list(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
    |> Enum.sort()
    |> Enum.map_join("&", fn
      {k, ""} ->
        URI.encode(k, &URI.char_unreserved?/1)

      {k, v} ->
        "#{URI.encode(k, &URI.char_unreserved?/1)}=#{URI.encode(v, &URI.char_unreserved?/1)}"
    end)
  end

  defp classify_body(""), do: {nil, false}
  defp classify_body(body) when is_binary(body), do: {nil, false}

  defp classify_body(body) when is_list(body) do
    if iodata?(body), do: {nil, false}, else: {"UNSIGNED-PAYLOAD", true}
  end

  defp classify_body(%Stream{}), do: {"UNSIGNED-PAYLOAD", true}
  defp classify_body(%{}), do: {"UNSIGNED-PAYLOAD", true}
  defp classify_body(body) when is_function(body), do: {"UNSIGNED-PAYLOAD", true}
  defp classify_body(_body), do: {nil, false}

  defp iodata?(list) do
    is_integer(IO.iodata_length(list))
  rescue
    _ -> false
  end

  defp resolve_path_style(nil, _sandbox_opts), do: false
  defp resolve_path_style(value, _sandbox_opts), do: value

  # ---------------------------------------------------------------------------
  # FACADE
  # ---------------------------------------------------------------------------

  defmacro __using__(opts \\ []) do
    quote do
      opts = unquote(opts)

      src_bucket = opts[:bucket] || opts[:source_bucket]
      dest_bucket = opts[:bucket] || opts[:destination_bucket] || src_bucket
      default_options = opts[:options] || []

      alias AwsSDK.S3

      @src_bucket src_bucket
      @dest_bucket dest_bucket
      @default_options default_options

      def list_buckets(opts \\ []) do
        opts
        |> with_default_options()
        |> S3.list_buckets()
      end

      def create_bucket(opts \\ []) do
        S3.create_bucket(source_bucket!(opts), with_default_options(opts))
      end

      def delete_bucket(opts \\ []) do
        S3.delete_bucket(source_bucket!(opts), with_default_options(opts))
      end

      def head_bucket(opts \\ []) do
        S3.head_bucket(source_bucket!(opts), with_default_options(opts))
      end

      def put_object(key, body, opts \\ []) do
        S3.put_object(source_bucket!(opts), key, body, with_default_options(opts))
      end

      def head_object(key, opts \\ []) do
        S3.head_object(source_bucket!(opts), key, with_default_options(opts))
      end

      def delete_object(key, opts \\ []) do
        S3.delete_object(source_bucket!(opts), key, with_default_options(opts))
      end

      def get_object(key, opts \\ []) do
        S3.get_object(source_bucket!(opts), key, with_default_options(opts))
      end

      def list_objects(opts \\ []) do
        S3.list_objects(source_bucket!(opts), with_default_options(opts))
      end

      def copy_object(dest_key, src_key, opts \\ []) do
        opts
        |> destination_bucket!()
        |> S3.copy_object(
          dest_key,
          source_bucket!(opts),
          src_key,
          with_default_options(opts)
        )
      end

      def presign(http_method, key, opts \\ []) do
        S3.presign(
          source_bucket!(opts),
          http_method,
          key,
          with_default_options(opts)
        )
      end

      def presign_post(key, opts \\ []) do
        S3.presign_post(source_bucket!(opts), key, with_default_options(opts))
      end

      def presign_part(object, upload_id, part_number, opts \\ []) do
        S3.presign_part(
          source_bucket!(opts),
          object,
          upload_id,
          part_number,
          with_default_options(opts)
        )
      end

      def create_multipart_upload(key, opts \\ []) do
        S3.create_multipart_upload(
          source_bucket!(opts),
          key,
          with_default_options(opts)
        )
      end

      def abort_multipart_upload(key, upload_id, opts \\ []) do
        S3.abort_multipart_upload(
          source_bucket!(opts),
          key,
          upload_id,
          with_default_options(opts)
        )
      end

      def upload_part(key, upload_id, part_number, body, opts \\ []) do
        S3.upload_part(
          source_bucket!(opts),
          key,
          upload_id,
          part_number,
          body,
          with_default_options(opts)
        )
      end

      def list_parts(key, upload_id, part_number_marker \\ nil, opts \\ []) do
        S3.list_parts(
          source_bucket!(opts),
          key,
          upload_id,
          part_number_marker,
          with_default_options(opts)
        )
      end

      def copy_part(dest_key, src_key, upload_id, part_number, src_range, opts) do
        opts
        |> destination_bucket!()
        |> S3.copy_part(
          dest_key,
          source_bucket!(opts),
          src_key,
          upload_id,
          part_number,
          src_range,
          with_default_options(opts)
        )
      end

      def copy_parts(dest_key, src_key, upload_id, content_length, opts \\ []) do
        opts
        |> destination_bucket!()
        |> S3.copy_parts(
          dest_key,
          source_bucket!(opts),
          src_key,
          upload_id,
          content_length,
          with_default_options(opts)
        )
      end

      def copy_object_multipart(dest_key, src_key, opts \\ []) do
        opts
        |> destination_bucket!()
        |> S3.copy_object_multipart(
          dest_key,
          source_bucket!(opts),
          src_key,
          with_default_options(opts)
        )
      end

      def complete_multipart_upload(key, upload_id, parts, opts \\ []) do
        S3.complete_multipart_upload(
          source_bucket!(opts),
          key,
          upload_id,
          parts,
          with_default_options(opts)
        )
      end

      def enable_event_bridge(opts \\ []) do
        S3.enable_event_bridge(source_bucket!(opts), with_default_options(opts))
      end

      def disable_event_bridge(opts \\ []) do
        S3.disable_event_bridge(source_bucket!(opts), with_default_options(opts))
      end

      def get_notification_configuration(opts \\ []) do
        S3.get_notification_configuration(
          source_bucket!(opts),
          with_default_options(opts)
        )
      end

      def put_public_access_block(opts \\ []) do
        S3.put_public_access_block(
          source_bucket!(opts),
          with_default_options(opts)
        )
      end

      def put_bucket_encryption(opts \\ []) do
        S3.put_bucket_encryption(source_bucket!(opts), with_default_options(opts))
      end

      def put_bucket_lifecycle_configuration(rules, opts \\ []) do
        S3.put_bucket_lifecycle_configuration(
          source_bucket!(opts),
          rules,
          with_default_options(opts)
        )
      end

      defp destination_bucket!(opts) do
        with nil <-
               opts[:bucket] ||
                 opts[:destination_bucket] ||
                 @dest_bucket ||
                 opts[:source_bucket] ||
                 @src_bucket do
          raise "Destination bucket not specified"
        end
      end

      defp source_bucket!(opts) do
        with nil <- opts[:bucket] || opts[:source_bucket] || @src_bucket do
          raise "Source bucket not specified"
        end
      end

      defp with_default_options(opts) do
        @default_options
        |> Keyword.merge(opts)
        |> Keyword.drop([:source_bucket, :destination_bucket])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # SANDBOX HELPERS
  # ---------------------------------------------------------------------------

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
    defdelegate sandbox_disabled?, to: AwsSDK.S3.Sandbox

    @doc false
    defdelegate sandbox_list_buckets_response(opts),
      to: AwsSDK.S3.Sandbox,
      as: :list_buckets_response

    @doc false
    defdelegate sandbox_create_bucket_response(bucket, opts),
      to: AwsSDK.S3.Sandbox,
      as: :create_bucket_response

    @doc false
    defdelegate sandbox_delete_bucket_response(bucket, opts),
      to: AwsSDK.S3.Sandbox,
      as: :delete_bucket_response

    @doc false
    defdelegate sandbox_put_object_response(bucket, key, body, opts),
      to: AwsSDK.S3.Sandbox,
      as: :put_object_response

    @doc false
    defdelegate sandbox_head_object_response(bucket, key, opts),
      to: AwsSDK.S3.Sandbox,
      as: :head_object_response

    @doc false
    defdelegate sandbox_delete_objects_response(bucket, objects, opts),
      to: AwsSDK.S3.Sandbox,
      as: :delete_objects_response

    @doc false
    defdelegate sandbox_delete_object_response(bucket, key, opts),
      to: AwsSDK.S3.Sandbox,
      as: :delete_object_response

    @doc false
    defdelegate sandbox_get_object_response(bucket, key, opts),
      to: AwsSDK.S3.Sandbox,
      as: :get_object_response

    @doc false
    defdelegate sandbox_list_objects_response(bucket, opts),
      to: AwsSDK.S3.Sandbox,
      as: :list_objects_response

    @doc false
    defdelegate sandbox_copy_object_response(dest_bucket, dest_key, src_bucket, src_key, opts),
      to: AwsSDK.S3.Sandbox,
      as: :copy_object_response

    @doc false
    defdelegate sandbox_presign_response(bucket, http_method, key, opts),
      to: AwsSDK.S3.Sandbox,
      as: :presign_response

    @doc false
    defdelegate sandbox_presign_post_response(bucket, key, opts),
      to: AwsSDK.S3.Sandbox,
      as: :presign_post_response

    @doc false
    defdelegate sandbox_presign_part_response(bucket, object, upload_id, part_number, opts),
      to: AwsSDK.S3.Sandbox,
      as: :presign_part_response

    @doc false
    defdelegate sandbox_create_multipart_upload_response(bucket, key, opts),
      to: AwsSDK.S3.Sandbox,
      as: :create_multipart_upload_response

    @doc false
    defdelegate sandbox_abort_multipart_upload_response(bucket, key, upload_id, opts),
      to: AwsSDK.S3.Sandbox,
      as: :abort_multipart_upload_response

    @doc false
    defdelegate sandbox_upload_part_response(bucket, key, upload_id, part_number, body, opts),
      to: AwsSDK.S3.Sandbox,
      as: :upload_part_response

    @doc false
    defdelegate sandbox_list_parts_response(bucket, key, upload_id, part_number_marker, opts),
      to: AwsSDK.S3.Sandbox,
      as: :list_parts_response

    @doc false
    defdelegate sandbox_copy_part_response(
                  dest_bucket,
                  dest_key,
                  src_bucket,
                  src_key,
                  upload_id,
                  part_number,
                  src_range,
                  opts
                ),
                to: AwsSDK.S3.Sandbox,
                as: :copy_part_response

    @doc false
    defdelegate sandbox_copy_parts_response(
                  dest_bucket,
                  dest_key,
                  src_bucket,
                  src_key,
                  upload_id,
                  content_length,
                  opts
                ),
                to: AwsSDK.S3.Sandbox,
                as: :copy_parts_response

    @doc false
    defdelegate sandbox_complete_multipart_upload_response(
                  bucket,
                  key,
                  upload_id,
                  parts,
                  opts
                ),
                to: AwsSDK.S3.Sandbox,
                as: :complete_multipart_upload_response

    # S3 EventBridge notification sandbox delegates
    @doc false
    defdelegate sandbox_enable_event_bridge_response(bucket, opts),
      to: AwsSDK.S3.Sandbox,
      as: :enable_event_bridge_response

    @doc false
    defdelegate sandbox_disable_event_bridge_response(bucket, opts),
      to: AwsSDK.S3.Sandbox,
      as: :disable_event_bridge_response

    @doc false
    defdelegate sandbox_get_notification_configuration_response(bucket, opts),
      to: AwsSDK.S3.Sandbox,
      as: :get_notification_configuration_response

    @doc false
    defdelegate sandbox_head_bucket_response(bucket, opts),
      to: AwsSDK.S3.Sandbox,
      as: :head_bucket_response

    @doc false
    defdelegate sandbox_put_public_access_block_response(bucket, opts),
      to: AwsSDK.S3.Sandbox,
      as: :put_public_access_block_response

    @doc false
    defdelegate sandbox_put_bucket_encryption_response(bucket, opts),
      to: AwsSDK.S3.Sandbox,
      as: :put_bucket_encryption_response

    @doc false
    defdelegate sandbox_put_bucket_lifecycle_configuration_response(bucket, rules, opts),
      to: AwsSDK.S3.Sandbox,
      as: :put_bucket_lifecycle_configuration_response
  else
    defp sandbox_disabled?, do: true

    defp sandbox_list_buckets_response(opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      options: #{inspect(opts)}
      """
    end

    defp sandbox_create_bucket_response(bucket, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_delete_bucket_response(bucket, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_put_object_response(bucket, key, body, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      key: #{inspect(key)}
      body: #{inspect(body)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_head_object_response(bucket, key, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      key: #{inspect(key)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_delete_object_response(bucket, key, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      key: #{inspect(key)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_delete_objects_response(bucket, objects, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      objects: #{inspect(objects)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_get_object_response(bucket, key, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      key: #{inspect(key)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_list_objects_response(bucket, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_copy_object_response(dest_bucket, dest_key, src_bucket, src_key, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      dest_bucket: #{inspect(dest_bucket)}
      dest_key: #{inspect(dest_key)}
      src_bucket: #{inspect(src_bucket)}
      src_key: #{inspect(src_key)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_presign_response(bucket, http_method, key, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      http_method: #{inspect(http_method)}
      key: #{inspect(key)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_presign_post_response(bucket, key, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      key: #{inspect(key)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_presign_part_response(bucket, object, upload_id, part_number, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      object: #{inspect(object)}
      upload_id: #{inspect(upload_id)}
      part_number: #{inspect(part_number)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_create_multipart_upload_response(bucket, key, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      key: #{inspect(key)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_abort_multipart_upload_response(bucket, key, upload_id, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      key: #{inspect(key)}
      upload_id: #{inspect(upload_id)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_upload_part_response(bucket, key, upload_id, part_number, body, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      key: #{inspect(key)}
      upload_id: #{inspect(upload_id)}
      part_number: #{inspect(part_number)}
      body: #{inspect(body)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_list_parts_response(bucket, key, upload_id, part_number_marker, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      key: #{inspect(key)}
      upload_id: #{inspect(upload_id)}
      part_number_marker: #{inspect(part_number_marker)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_copy_part_response(
           dest_bucket,
           dest_key,
           src_bucket,
           src_key,
           upload_id,
           part_number,
           src_range,
           opts
         ) do
      raise """
      Cannot use sandbox mode outside of test environment.

      dest_bucket: #{inspect(dest_bucket)}
      dest_key: #{inspect(dest_key)}
      src_bucket: #{inspect(src_bucket)}
      src_key: #{inspect(src_key)}
      upload_id: #{inspect(upload_id)}
      part_number: #{inspect(part_number)}
      src_range: #{inspect(src_range)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_copy_parts_response(
           dest_bucket,
           dest_key,
           src_bucket,
           src_key,
           upload_id,
           content_length,
           opts
         ) do
      raise """
      Cannot use sandbox mode outside of test environment.

      dest_bucket: #{inspect(dest_bucket)}
      dest_key: #{inspect(dest_key)}
      src_bucket: #{inspect(src_bucket)}
      src_key: #{inspect(src_key)}
      upload_id: #{inspect(upload_id)}
      content_length: #{inspect(content_length)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_complete_multipart_upload_response(bucket, key, upload_id, parts, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      key: #{inspect(key)}
      upload_id: #{inspect(upload_id)}
      parts: #{inspect(parts)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_enable_event_bridge_response(bucket, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_disable_event_bridge_response(bucket, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_get_notification_configuration_response(bucket, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_head_bucket_response(bucket, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_put_public_access_block_response(bucket, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_put_bucket_encryption_response(bucket, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      options: #{inspect(opts)}
      """
    end

    defp sandbox_put_bucket_lifecycle_configuration_response(bucket, rules, opts) do
      raise """
      Cannot use sandbox mode outside of test environment.

      bucket: #{inspect(bucket)}
      rules: #{inspect(rules)}
      options: #{inspect(opts)}
      """
    end
  end

  # ---------------------------------------------------------------------------
  # Overrides / response handling
  # ---------------------------------------------------------------------------

  @override_keys [:headers, :body, :http, :url, :stream_upload, :stream_response, :payload_hash]

  defp apply_overrides(op, overrides) do
    Enum.reduce(@override_keys, op, fn key, acc ->
      case Keyword.fetch(overrides, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end
end
