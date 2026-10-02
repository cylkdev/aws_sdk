defmodule AwsSDK.S3.XMLBuilder do
  @moduledoc """
  Builds the XML request bodies that S3 expects for write operations whose
  payload is an XML document: `PutPublicAccessBlock`, `PutBucketEncryption`,
  `PutBucketLifecycleConfiguration`, and `DeleteObjects`.

  Counterpart to `AwsSDK.S3.XMLParser`, which extracts data from the XML
  responses S3 returns. Each builder is a pure function over Elixir data and
  returns a binary that can be asserted on directly in tests, independently
  of any HTTP transport.
  """

  @xmlns "http://s3.amazonaws.com/doc/2006-03-01/"

  @doc """
  Builds the `<Delete>` XML body for `DeleteObjects`.

  Each object is a key binary or a `%{key: key, version_id: version_id}`
  map. `quiet` asks S3 to omit per-key success entries from the response.

  ## Examples

      AwsSDK.S3.XMLBuilder.build_delete(["a.txt", %{key: "b.txt", version_id: "v1"}], false)
      #=> ~s(<Delete xmlns="http://s3.amazonaws.com/doc/2006-03-01/">) <>
      #=>   "<Object><Key>a.txt</Key></Object>" <>
      #=>   "<Object><Key>b.txt</Key><VersionId>v1</VersionId></Object>" <>
      #=>   "</Delete>"
  """
  @spec build_delete(objects :: [String.t() | map()], quiet :: boolean()) :: binary()
  def build_delete(objects, quiet) when is_list(objects) and is_boolean(quiet) do
    objects_xml = Enum.map_join(objects, &delete_object_xml/1)
    quiet_xml = if quiet, do: "<Quiet>true</Quiet>", else: ""

    "<Delete xmlns=\"#{@xmlns}\">#{objects_xml}#{quiet_xml}</Delete>"
  end

  defp delete_object_xml(key) when is_binary(key) do
    "<Object><Key>#{key}</Key></Object>"
  end

  defp delete_object_xml(%{key: key} = object) do
    version_xml =
      case object[:version_id] do
        nil -> ""
        version_id -> "<VersionId>#{version_id}</VersionId>"
      end

    "<Object><Key>#{key}</Key>#{version_xml}</Object>"
  end

  @doc """
  Builds the `<PublicAccessBlockConfiguration>` XML body for
  `PutPublicAccessBlock`.

  Only the flags you supply are emitted. AWS documents all four as optional
  and leaves an omitted flag unchanged, so nothing is defaulted here —
  defaulting them all to `true` would mean setting one flag silently flipped
  the other three.

  ## Options

    * `:block_public_acls` - Optional boolean.
    * `:ignore_public_acls` - Optional boolean.
    * `:block_public_policy` - Optional boolean.
    * `:restrict_public_buckets` - Optional boolean.

  ## Examples

      AwsSDK.S3.XMLBuilder.build_public_access_block(
        block_public_acls: true,
        ignore_public_acls: true
      )
      #=> ~s(<PublicAccessBlockConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">) <>
      #=>   "<BlockPublicAcls>true</BlockPublicAcls>" <>
      #=>   "<IgnorePublicAcls>true</IgnorePublicAcls>" <>
      #=>   "</PublicAccessBlockConfiguration>"

  Only the flags supplied are emitted; omitted flags are left out entirely
  rather than sent as false.
  """
  @spec build_public_access_block(opts :: keyword()) :: binary()
  # Only the flags the caller supplied are emitted. Defaulting them all to
  # `true` meant setting one flag silently flipped the other three.
  def build_public_access_block(opts \\ []) do
    inner =
      [
        {"BlockPublicAcls", opts[:block_public_acls]},
        {"IgnorePublicAcls", opts[:ignore_public_acls]},
        {"BlockPublicPolicy", opts[:block_public_policy]},
        {"RestrictPublicBuckets", opts[:restrict_public_buckets]}
      ]
      |> Enum.reject(fn {_element, value} -> is_nil(value) end)
      |> Enum.map_join(fn {element, value} -> "<#{element}>#{value}</#{element}>" end)

    "<PublicAccessBlockConfiguration xmlns=\"#{@xmlns}\">#{inner}</PublicAccessBlockConfiguration>"
  end

  @doc """
  Builds the `<ServerSideEncryptionConfiguration>` XML body for
  `PutBucketEncryption`.

  ## Options

    * `:sse_algorithm` - One of `"AES256"` (default), `"aws:kms"`, or `"aws:kms:dsse"`.
    * `:kms_master_key_id` - Required when `:sse_algorithm` is a KMS variant.
    * `:bucket_key_enabled` - Optional boolean.

  ## Examples

      AwsSDK.S3.XMLBuilder.build_bucket_encryption([])
      #=> ~s(<ServerSideEncryptionConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">) <>
      #=>   "<Rule><ApplyServerSideEncryptionByDefault>" <>
      #=>   "<SSEAlgorithm>AES256</SSEAlgorithm>" <>
      #=>   "</ApplyServerSideEncryptionByDefault></Rule>" <>
      #=>   "</ServerSideEncryptionConfiguration>"

      AwsSDK.S3.XMLBuilder.build_bucket_encryption(
        sse_algorithm: "aws:kms",
        kms_master_key_id: "arn:aws:kms:us-east-1:123456789012:key/abc",
        bucket_key_enabled: true
      )
      #=> "...<SSEAlgorithm>aws:kms</SSEAlgorithm>" <>
      #=>   "<KMSMasterKeyID>arn:aws:kms:us-east-1:123456789012:key/abc</KMSMasterKeyID>" <>
      #=>   "...<BucketKeyEnabled>true</BucketKeyEnabled>..."

  Defaults to `AES256` when no algorithm is given, rather than emitting an
  empty element AWS would reject.
  """
  @spec build_bucket_encryption(opts :: keyword()) :: binary()
  def build_bucket_encryption(opts \\ []) do
    # `SSEAlgorithm` is a required member of `ServerSideEncryptionByDefault`.
    # Interpolating a nil produced `<SSEAlgorithm></SSEAlgorithm>` and S3
    # answered MalformedXML, so the documented one-argument call never worked.
    sse_algorithm = opts[:sse_algorithm] || "AES256"
    kms_master_key_id = opts[:kms_master_key_id]
    bucket_key_enabled = opts[:bucket_key_enabled]

    apply_default =
      "<SSEAlgorithm>#{sse_algorithm}</SSEAlgorithm>" <>
        kms_master_key_id_xml(kms_master_key_id)

    rule_inner =
      "<ApplyServerSideEncryptionByDefault>#{apply_default}</ApplyServerSideEncryptionByDefault>" <>
        bucket_key_enabled_xml(bucket_key_enabled)

    "<ServerSideEncryptionConfiguration xmlns=\"#{@xmlns}\"><Rule>#{rule_inner}</Rule></ServerSideEncryptionConfiguration>"
  end

  @doc """
  Builds the `<LifecycleConfiguration>` XML body for
  `PutBucketLifecycleConfiguration`.

  See `AwsSDK.S3.put_bucket_lifecycle_configuration/3` for the supported rule
  shape.

  ## Examples

      AwsSDK.S3.XMLBuilder.build_lifecycle_configuration([
        %{id: "expire", filter: %{prefix: "incoming/"}, expiration: %{days: 30}}
      ])
      #=> ~s(<LifecycleConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">) <>
      #=>   "<Rule><ID>expire</ID>" <>
      #=>   "<Filter><Prefix>incoming/</Prefix></Filter>" <>
      #=>   "<Status>Enabled</Status>" <>
      #=>   "<Expiration><Days>30</Days></Expiration>" <>
      #=>   "</Rule></LifecycleConfiguration>"

  A rule with no `:status` defaults to `Enabled`.
  """
  @spec build_lifecycle_configuration(rules :: list(map())) :: binary()
  def build_lifecycle_configuration(rules) when is_list(rules) do
    rules_xml = Enum.map_join(rules, "", &lifecycle_rule_xml/1)
    "<LifecycleConfiguration xmlns=\"#{@xmlns}\">#{rules_xml}</LifecycleConfiguration>"
  end

  @doc """
  Builds the `<VersioningConfiguration>` XML body for `PutBucketVersioning`.

  `status` is `"Enabled"` or `"Suspended"`. `MfaDelete` is not supported.

  ## Examples

      AwsSDK.S3.XMLBuilder.build_versioning_configuration("Enabled")
      #=> ~s(<VersioningConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">) <>
      #=>   "<Status>Enabled</Status></VersioningConfiguration>"
  """
  @spec build_versioning_configuration(status :: binary()) :: binary()
  def build_versioning_configuration(status) when status in ["Enabled", "Suspended"] do
    "<VersioningConfiguration xmlns=\"#{@xmlns}\"><Status>#{status}</Status></VersioningConfiguration>"
  end

  defp kms_master_key_id_xml(nil), do: ""
  defp kms_master_key_id_xml(id), do: "<KMSMasterKeyID>#{xml_escape(id)}</KMSMasterKeyID>"

  defp bucket_key_enabled_xml(nil), do: ""

  defp bucket_key_enabled_xml(value) when is_boolean(value),
    do: "<BucketKeyEnabled>#{value}</BucketKeyEnabled>"

  defp lifecycle_rule_xml(rule) do
    id = Map.fetch!(rule, :id)
    # Documented as defaulting to "Enabled"; `Map.fetch!` raised a KeyError
    # instead, so the documented rule shape did not work.
    status = Map.get(rule, :status, "Enabled")
    filter = Map.get(rule, :filter, %{})

    parts =
      [
        "<ID>#{xml_escape(id)}</ID>",
        lifecycle_filter_xml(filter),
        "<Status>#{status}</Status>",
        expiration_xml(rule[:expiration]),
        transitions_xml(rule[:transitions]),
        noncurrent_version_expiration_xml(rule[:noncurrent_version_expiration]),
        noncurrent_version_transitions_xml(rule[:noncurrent_version_transitions]),
        abort_incomplete_multipart_xml(rule[:abort_incomplete_multipart_upload])
      ]
      |> Enum.reject(&(&1 === ""))
      |> Enum.join()

    "<Rule>#{parts}</Rule>"
  end

  defp lifecycle_filter_xml(filter) when map_size(filter) === 0, do: "<Filter></Filter>"

  defp lifecycle_filter_xml(%{prefix: prefix} = filter) when map_size(filter) === 1 do
    "<Filter><Prefix>#{xml_escape(prefix)}</Prefix></Filter>"
  end

  defp lifecycle_filter_xml(%{tag: %{key: k, value: v}} = filter) when map_size(filter) === 1 do
    "<Filter><Tag><Key>#{xml_escape(k)}</Key><Value>#{xml_escape(v)}</Value></Tag></Filter>"
  end

  defp lifecycle_filter_xml(%{object_size_greater_than: n} = filter)
       when map_size(filter) === 1 do
    "<Filter><ObjectSizeGreaterThan>#{n}</ObjectSizeGreaterThan></Filter>"
  end

  defp lifecycle_filter_xml(%{object_size_less_than: n} = filter)
       when map_size(filter) === 1 do
    "<Filter><ObjectSizeLessThan>#{n}</ObjectSizeLessThan></Filter>"
  end

  defp lifecycle_filter_xml(%{and: and_filter}) do
    "<Filter><And>#{and_filter_inner(and_filter)}</And></Filter>"
  end

  defp and_filter_inner(and_filter) do
    [
      and_filter_prefix(and_filter[:prefix]),
      and_filter_size(:object_size_greater_than, and_filter[:object_size_greater_than]),
      and_filter_size(:object_size_less_than, and_filter[:object_size_less_than]),
      and_filter_tags(and_filter[:tags] || [])
    ]
    |> Enum.reject(&(&1 === ""))
    |> Enum.join()
  end

  defp and_filter_prefix(nil), do: ""
  defp and_filter_prefix(prefix), do: "<Prefix>#{xml_escape(prefix)}</Prefix>"

  defp and_filter_size(_key, nil), do: ""

  defp and_filter_size(:object_size_greater_than, n),
    do: "<ObjectSizeGreaterThan>#{n}</ObjectSizeGreaterThan>"

  defp and_filter_size(:object_size_less_than, n),
    do: "<ObjectSizeLessThan>#{n}</ObjectSizeLessThan>"

  defp and_filter_tags(tags) do
    Enum.map_join(tags, "", fn %{key: k, value: v} ->
      "<Tag><Key>#{xml_escape(k)}</Key><Value>#{xml_escape(v)}</Value></Tag>"
    end)
  end

  defp expiration_xml(nil), do: ""

  defp expiration_xml(expiration) do
    inner =
      [
        days_xml(expiration[:days]),
        date_xml(expiration[:date]),
        expired_marker_xml(expiration[:expired_object_delete_marker])
      ]
      |> Enum.reject(&(&1 === ""))
      |> Enum.join()

    "<Expiration>#{inner}</Expiration>"
  end

  defp days_xml(nil), do: ""
  defp days_xml(n) when is_integer(n), do: "<Days>#{n}</Days>"

  defp date_xml(nil), do: ""
  defp date_xml(date), do: "<Date>#{date}</Date>"

  defp expired_marker_xml(nil), do: ""

  defp expired_marker_xml(value) when is_boolean(value),
    do: "<ExpiredObjectDeleteMarker>#{value}</ExpiredObjectDeleteMarker>"

  defp transitions_xml(nil), do: ""

  defp transitions_xml(transitions) when is_list(transitions) do
    Enum.map_join(transitions, "", fn t ->
      inner =
        [
          days_xml(t[:days]),
          date_xml(t[:date]),
          storage_class_xml(t[:storage_class])
        ]
        |> Enum.reject(&(&1 === ""))
        |> Enum.join()

      "<Transition>#{inner}</Transition>"
    end)
  end

  defp storage_class_xml(nil), do: ""
  defp storage_class_xml(class), do: "<StorageClass>#{class}</StorageClass>"

  defp noncurrent_version_expiration_xml(nil), do: ""

  defp noncurrent_version_expiration_xml(%{} = config) do
    inner =
      [
        noncurrent_days_xml(config[:noncurrent_days]),
        newer_versions_xml(config[:newer_noncurrent_versions])
      ]
      |> Enum.reject(&(&1 === ""))
      |> Enum.join()

    "<NoncurrentVersionExpiration>#{inner}</NoncurrentVersionExpiration>"
  end

  defp noncurrent_version_transitions_xml(nil), do: ""

  defp noncurrent_version_transitions_xml(transitions) when is_list(transitions) do
    Enum.map_join(transitions, "", fn t ->
      inner =
        [
          noncurrent_days_xml(t[:noncurrent_days]),
          newer_versions_xml(t[:newer_noncurrent_versions]),
          storage_class_xml(t[:storage_class])
        ]
        |> Enum.reject(&(&1 === ""))
        |> Enum.join()

      "<NoncurrentVersionTransition>#{inner}</NoncurrentVersionTransition>"
    end)
  end

  defp noncurrent_days_xml(nil), do: ""
  defp noncurrent_days_xml(n) when is_integer(n), do: "<NoncurrentDays>#{n}</NoncurrentDays>"

  defp newer_versions_xml(nil), do: ""

  defp newer_versions_xml(n) when is_integer(n),
    do: "<NewerNoncurrentVersions>#{n}</NewerNoncurrentVersions>"

  defp abort_incomplete_multipart_xml(nil), do: ""

  defp abort_incomplete_multipart_xml(%{days_after_initiation: n}) when is_integer(n) do
    "<AbortIncompleteMultipartUpload><DaysAfterInitiation>#{n}</DaysAfterInitiation></AbortIncompleteMultipartUpload>"
  end

  defp xml_escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp xml_escape(value), do: xml_escape(to_string(value))
end
