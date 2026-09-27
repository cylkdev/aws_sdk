defmodule AwsSDK.Logs do
  @moduledoc """
  `AwsSDK.Logs` provides an API for Amazon CloudWatch Logs.

  This API calls the AWS CloudWatch Logs JSON 1.1 API directly over HTTP using
  `Finch` as the HTTP client (via `AwsSDK.HTTP`), Erlang's built-in `:json` for
  encoding/decoding (OTP 27+ required), and a SigV4 signer (`AwsSDK.Signer`). It
  provides consistent error handling, response deserialization, and sandbox
  support.

  CloudWatch Logs uses camelCase (lowercase first letter) keys on the wire.

  ## Shared Options

  Credentials and region are flat top-level opts on every call (ex_aws shape).
  Each accepts a literal, a source tuple, or a list of sources (first
  non-nil wins):

    - `:access_key_id`, `:secret_access_key`, `:security_token`, `:region` -
      Sources: literal binary, `{:system, "ENV"}`, `:instance_role`,
      `:ecs_task_role`, `{:awscli, profile}` / `{:awscli, profile, ttl}`,
      a module, or a list of any of these. Map-returning sources merge
      into the outer config. `{:awscli, _}` is not in the default chain —
      callers opt in explicitly.

  The following options are also available:

    - `:logs` - A keyword list of CloudWatch Logs endpoint overrides.
      Supported keys: `:scheme`, `:host`, `:port`. Credentials are not
      read from this sub-list; use the top-level keys above.

    - `:sandbox` - A keyword list to override sandbox configuration.
        - `:enabled` - Whether sandbox mode is enabled.
        - `:scheme` - The sandbox scheme.
        - `:host` - The sandbox host.
        - `:port` - The sandbox port.

  ## Sandbox

  Set `sandbox: [enabled: true]` to activate sandbox mode.

  ### Setup

  Add the following to your `test_helper.exs`:

      AwsSDK.Logs.Sandbox.start_link()

  ### Usage

      setup do
        AwsSDK.Logs.Sandbox.set_create_log_group_responses([
          {"my-group", fn -> {:ok, %{}} end}
        ])
      end

      test "creates a log group" do
        assert {:ok, %{}} =
                 AwsSDK.Logs.create_log_group("my-group",
                   sandbox: [enabled: true]
                 )
      end
  """

  alias AwsSDK.Client
  alias AwsSDK.Operation
  alias ExUtils.Serializer

  @service "logs"
  @content_type "application/x-amz-json-1.1"
  @target_prefix "Logs_20140328"

  # Log Groups

  @doc """
  Creates a log group.

  ## Options

    * `:kms_key_id` - KMS key ARN for log group encryption.
    * `:tags` - Map of tags to attach.

  ## Examples

      AwsSDK.Logs.create_log_group("/aws/app/prod")
      #=> {:ok, %{}}

  AWS returns an empty body, and rejects a name that already exists.
  """
  @spec create_log_group(name :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def create_log_group(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_create_log_group_response(name, opts)
    else
      do_create_log_group(name, opts)
    end
  end

  defp do_create_log_group(name, opts) do
    data =
      %{"logGroupName" => name}
      |> maybe_put("kmsKeyId", opts[:kms_key_id])
      |> maybe_put("tags", opts[:tags])

    with {:ok, op} <- build_operation("CreateLogGroup", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deletes a log group.

  ## Examples

      AwsSDK.Logs.delete_log_group("/aws/app/prod")
      #=> {:ok, %{}}

  Deletes every stream and event in the group.
  """
  @spec delete_log_group(name :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def delete_log_group(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_delete_log_group_response(name, opts)
    else
      do_delete_log_group(name, opts)
    end
  end

  defp do_delete_log_group(name, opts) do
    with {:ok, op} <- build_operation("DeleteLogGroup", %{"logGroupName" => name}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists log groups, optionally filtered by name prefix.

  ## Options

    * `:log_group_name_prefix` - Filter by prefix.
    * `:limit` - Max results per page.
    * `:next_token` - Pagination token.

  ## Examples

      AwsSDK.Logs.describe_log_groups(log_group_name_prefix: "/aws/app/")
      #=> {:ok,
      #=>  %{
      #=>    log_groups: [
      #=>      %{
      #=>        log_group_name: "/aws/app/prod",
      #=>        arn: "arn:aws:logs:us-east-1:123456789012:log-group:/aws/app/prod:*",
      #=>        creation_time: 1_767_225_600_000,
      #=>        retention_in_days: 30,
      #=>        metric_filter_count: 0,
      #=>        stored_bytes: 1_048_576
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}

  `:retention_in_days` is absent when the group never expires.
  """
  @spec describe_log_groups(opts :: keyword()) ::
          {:ok, %{log_groups: list(map()), next_token: String.t() | nil}} | {:error, term()}
  def describe_log_groups(opts \\ []) do
    if sandbox?(opts) do
      sandbox_describe_log_groups_response(opts)
    else
      do_describe_log_groups(opts)
    end
  end

  defp do_describe_log_groups(opts) do
    data =
      %{}
      |> maybe_put("logGroupNamePrefix", opts[:log_group_name_prefix])
      |> maybe_put("limit", opts[:limit])
      |> maybe_put("nextToken", opts[:next_token])

    with {:ok, op} <- build_operation("DescribeLogGroups", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Sets retention for a log group, in days (e.g. 1, 7, 30, 90, 365).

  ## Examples

      AwsSDK.Logs.put_retention_policy("/aws/app/prod", 30)
      #=> {:ok, %{}}

  AWS accepts only specific values (1, 3, 5, 7, 14, 30, 60, 90, ...).
  """
  @spec put_retention_policy(name :: String.t(), days :: pos_integer(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def put_retention_policy(name, days, opts \\ []) when is_binary(name) and is_integer(days) do
    if sandbox?(opts) do
      sandbox_put_retention_policy_response(name, days, opts)
    else
      do_put_retention_policy(name, days, opts)
    end
  end

  defp do_put_retention_policy(name, days, opts) do
    data = %{"logGroupName" => name, "retentionInDays" => days}

    with {:ok, op} <- build_operation("PutRetentionPolicy", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Removes the retention policy from a log group (reverts to never expire).

  ## Examples

      AwsSDK.Logs.delete_retention_policy("/aws/app/prod")
      #=> {:ok, %{}}

  Events in the group then never expire.
  """
  @spec delete_retention_policy(name :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def delete_retention_policy(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_delete_retention_policy_response(name, opts)
    else
      do_delete_retention_policy(name, opts)
    end
  end

  defp do_delete_retention_policy(name, opts) do
    with {:ok, op} <- build_operation("DeleteRetentionPolicy", %{"logGroupName" => name}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # Log Streams

  @doc """
  Creates a log stream inside a log group.

  ## Examples

      AwsSDK.Logs.create_log_stream("/aws/app/prod", "instance/i-1234567890abcdef0")
      #=> {:ok, %{}}
  """
  @spec create_log_stream(group :: String.t(), stream :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def create_log_stream(group, stream, opts \\ []) when is_binary(group) and is_binary(stream) do
    if sandbox?(opts) do
      sandbox_create_log_stream_response(group, stream, opts)
    else
      do_create_log_stream(group, stream, opts)
    end
  end

  defp do_create_log_stream(group, stream, opts) do
    data = %{"logGroupName" => group, "logStreamName" => stream}

    with {:ok, op} <- build_operation("CreateLogStream", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deletes a log stream.

  ## Examples

      AwsSDK.Logs.delete_log_stream("/aws/app/prod", "instance/i-1234567890abcdef0")
      #=> {:ok, %{}}
  """
  @spec delete_log_stream(group :: String.t(), stream :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def delete_log_stream(group, stream, opts \\ []) when is_binary(group) and is_binary(stream) do
    if sandbox?(opts) do
      sandbox_delete_log_stream_response(group, stream, opts)
    else
      do_delete_log_stream(group, stream, opts)
    end
  end

  defp do_delete_log_stream(group, stream, opts) do
    data = %{"logGroupName" => group, "logStreamName" => stream}

    with {:ok, op} <- build_operation("DeleteLogStream", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists log streams for a log group.

  ## Options

    * `:log_stream_name_prefix` - Filter by prefix.
    * `:order_by` - `"LogStreamName"` or `"LastEventTime"`.
    * `:descending` - Boolean.
    * `:limit` - Max results per page.
    * `:next_token` - Pagination token.

  ## Examples

      AwsSDK.Logs.describe_log_streams("/aws/app/prod",
        order_by: "LastEventTime",
        descending: true
      )
      #=> {:ok,
      #=>  %{
      #=>    log_streams: [
      #=>      %{
      #=>        log_stream_name: "instance/i-1234567890abcdef0",
      #=>        arn: "arn:aws:logs:us-east-1:123456789012:log-group:/aws/app/prod:log-stream:instance/i-1234567890abcdef0",
      #=>        creation_time: 1_767_225_600_000,
      #=>        first_event_timestamp: 1_767_225_601_000,
      #=>        last_event_timestamp: 1_767_229_200_000,
      #=>        last_ingestion_time: 1_767_229_201_000,
      #=>        upload_sequence_token: "49590..."
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}

  Timestamps are milliseconds since the epoch, as AWS sends them.
  """
  @spec describe_log_streams(group :: String.t(), opts :: keyword()) ::
          {:ok, %{log_streams: list(map()), next_token: String.t() | nil}} | {:error, term()}
  def describe_log_streams(group, opts \\ []) when is_binary(group) do
    if sandbox?(opts) do
      sandbox_describe_log_streams_response(group, opts)
    else
      do_describe_log_streams(group, opts)
    end
  end

  defp do_describe_log_streams(group, opts) do
    data =
      %{"logGroupName" => group}
      |> maybe_put("logStreamNamePrefix", opts[:log_stream_name_prefix])
      |> maybe_put("orderBy", opts[:order_by])
      |> maybe_put("descending", opts[:descending])
      |> maybe_put("limit", opts[:limit])
      |> maybe_put("nextToken", opts[:next_token])

    with {:ok, op} <- build_operation("DescribeLogStreams", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # Log Events

  @doc """
  Writes log events to a log stream.

  ## Arguments

    * `group` - Log group name.
    * `stream` - Log stream name.
    * `events` - List of maps with `:timestamp` (ms since epoch) and `:message`.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.Logs.put_log_events("/aws/app/prod", "instance/i-1234567890abcdef0", [
        %{timestamp: 1_767_229_200_000, message: "boot complete"},
        %{timestamp: 1_767_229_201_000, message: "listening on :4000"}
      ])
      #=> {:ok,
      #=>  %{
      #=>    next_sequence_token: "49590...",
      #=>    rejected_log_events_info: nil
      #=>  }}

  Events must be in ascending timestamp order. Events AWS refuses are
  reported in `:rejected_log_events_info` rather than as an error.
  """
  @spec put_log_events(
          group :: String.t(),
          stream :: String.t(),
          events :: list(map()),
          opts :: keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def put_log_events(group, stream, [_ | _] = events, opts \\ [])
      when is_binary(group) and is_binary(stream) do
    if sandbox?(opts) do
      sandbox_put_log_events_response(group, stream, events, opts)
    else
      do_put_log_events(group, stream, events, opts)
    end
  end

  defp do_put_log_events(group, stream, events, opts) do
    data = %{
      "logGroupName" => group,
      "logStreamName" => stream,
      "logEvents" => Enum.map(events, &camelize_keys/1)
    }

    with {:ok, op} <- build_operation("PutLogEvents", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Reads log events from a log stream.

  ## Options

    * `:start_time` / `:end_time` - Epoch milliseconds.
    * `:start_from_head` - Boolean; read oldest first.
    * `:limit` - Max events per page.
    * `:next_token` - Pagination token.

  ## Examples

      AwsSDK.Logs.get_log_events("/aws/app/prod", "instance/i-1234567890abcdef0",
        limit: 100,
        start_from_head: true
      )
      #=> {:ok,
      #=>  %{
      #=>    events: [
      #=>      %{
      #=>        timestamp: 1_767_229_200_000,
      #=>        message: "boot complete",
      #=>        ingestion_time: 1_767_229_200_500
      #=>      }
      #=>    ],
      #=>    next_forward_token: "f/37...",
      #=>    next_backward_token: "b/37..."
      #=>  }}

  Both tokens are always returned; paging past the end yields the same token
  and an empty `:events`, which is how you detect the end.
  """
  @spec get_log_events(group :: String.t(), stream :: String.t(), opts :: keyword()) ::
          {:ok, %{events: list(map()), next_forward_token: String.t() | nil}} | {:error, term()}
  def get_log_events(group, stream, opts \\ []) when is_binary(group) and is_binary(stream) do
    if sandbox?(opts) do
      sandbox_get_log_events_response(group, stream, opts)
    else
      do_get_log_events(group, stream, opts)
    end
  end

  defp do_get_log_events(group, stream, opts) do
    data =
      %{"logGroupName" => group, "logStreamName" => stream}
      |> maybe_put("startTime", opts[:start_time])
      |> maybe_put("endTime", opts[:end_time])
      |> maybe_put("startFromHead", opts[:start_from_head])
      |> maybe_put("limit", opts[:limit])
      |> maybe_put("nextToken", opts[:next_token])

    with {:ok, op} <- build_operation("GetLogEvents", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Searches log events across one or more streams in a group.

  ## Options

    * `:filter_pattern` - CloudWatch Logs filter syntax.
    * `:log_stream_names` - List of stream names to search.
    * `:start_time` / `:end_time` - Epoch milliseconds.
    * `:limit` - Max events per page.
    * `:next_token` - Pagination token.

  ## Examples

      AwsSDK.Logs.filter_log_events("/aws/app/prod",
        filter_pattern: "ERROR",
        start_time: 1_767_225_600_000,
        end_time: 1_767_229_200_000
      )
      #=> {:ok,
      #=>  %{
      #=>    events: [
      #=>      %{
      #=>        log_stream_name: "instance/i-1234567890abcdef0",
      #=>        timestamp: 1_767_229_100_000,
      #=>        message: "ERROR database unreachable",
      #=>        ingestion_time: 1_767_229_100_500,
      #=>        event_id: "37201234567890123456789012345678901234567890123456789012"
      #=>      }
      #=>    ],
      #=>    searched_log_streams: [],
      #=>    next_token: nil
      #=>  }}

  Unlike `get_log_events/3`, this searches every stream in the group, so each
  event carries its `:log_stream_name`.
  """
  @spec filter_log_events(group :: String.t(), opts :: keyword()) ::
          {:ok, %{events: list(map()), next_token: String.t() | nil}} | {:error, term()}
  def filter_log_events(group, opts \\ []) when is_binary(group) do
    if sandbox?(opts) do
      sandbox_filter_log_events_response(group, opts)
    else
      do_filter_log_events(group, opts)
    end
  end

  defp do_filter_log_events(group, opts) do
    data =
      %{"logGroupName" => group}
      |> maybe_put("filterPattern", opts[:filter_pattern])
      |> maybe_put("logStreamNames", opts[:log_stream_names])
      |> maybe_put("startTime", opts[:start_time])
      |> maybe_put("endTime", opts[:end_time])
      |> maybe_put("limit", opts[:limit])
      |> maybe_put("nextToken", opts[:next_token])

    with {:ok, op} <- build_operation("FilterLogEvents", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # Insights Queries

  @doc """
  Starts a CloudWatch Logs Insights query against a single log group.

  Maps to AWS `StartQuery` with `logGroupName`. AWS accepts exactly one of
  `logGroupName`, `logGroupNames` or `logGroupIdentifiers` (or a `SOURCE`
  command in the query itself), so each form is its own function:
  `start_query_for_log_groups/5` and `start_query_by_identifiers/5`.

  ## Arguments

    * `group` - Log group to query.
    * `start_time` / `end_time` - Epoch seconds.
    * `query` - Logs Insights query string.
    * `opts` - May include `:limit`.

  ## Examples

      AwsSDK.Logs.start_query(
        "/aws/app/prod",
        1_767_225_600,
        1_767_229_200,
        "fields @timestamp, @message | filter @message like /ERROR/ | limit 20"
      )
      #=> {:ok, %{query_id: "12ab3456-12ab-123a-789e-1234567890ab"}}

  Returns immediately with a query ID; poll `get_query_results/2` until the
  status is terminal.
  """
  @spec start_query(
          group :: String.t(),
          start_time :: non_neg_integer(),
          end_time :: non_neg_integer(),
          query :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, %{query_id: String.t()}} | {:error, term()}
  def start_query(group, start_time, end_time, query, opts \\ [])
      when is_binary(group) and is_integer(start_time) and is_integer(end_time) and
             is_binary(query) do
    if sandbox?(opts) do
      sandbox_start_query_response(group, start_time, end_time, query, opts)
    else
      do_start_query(%{"logGroupName" => group}, start_time, end_time, query, opts)
    end
  end

  @doc """
  Starts an Insights query across several log groups by name.

  Maps to AWS `StartQuery` with `logGroupNames`.

  ## Examples

      AwsSDK.Logs.start_query_for_log_groups(
        ["/aws/app/prod", "/aws/app/worker"],
        1_767_225_600,
        1_767_229_200,
        "fields @timestamp, @message | filter @message like /ERROR/"
      )
      #=> {:ok, %{query_id: "12ab3456-12ab-123a-789e-1234567890ab"}}

  Returns immediately with a query ID; poll `get_query_results/2` until the
  status is terminal.

  Sends `logGroupNames`; use `start_query_by_identifiers/4` to query by ARN.
  """
  @spec start_query_for_log_groups(
          groups :: [String.t()],
          start_time :: non_neg_integer(),
          end_time :: non_neg_integer(),
          query :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, %{query_id: String.t()}} | {:error, term()}
  def start_query_for_log_groups([_ | _] = groups, start_time, end_time, query, opts \\ []) do
    if sandbox?(opts) do
      sandbox_start_query_for_log_groups_response(groups, start_time, end_time, query, opts)
    else
      do_start_query(%{"logGroupNames" => groups}, start_time, end_time, query, opts)
    end
  end

  @doc """
  Starts an Insights query by log group identifier (ARN), which is how
  cross-account queries are expressed.

  Maps to AWS `StartQuery` with `logGroupIdentifiers`.

  ## Examples

      AwsSDK.Logs.start_query_by_identifiers(
        ["arn:aws:logs:us-east-1:123456789012:log-group:/aws/app/prod"],
        1_767_225_600,
        1_767_229_200,
        "fields @timestamp, @message"
      )
      #=> {:ok, %{query_id: "12ab3456-12ab-123a-789e-1234567890ab"}}

  Returns immediately with a query ID; poll `get_query_results/2` until the
  status is terminal.

  Sends `logGroupIdentifiers`, which is the only form that can reach a log
  group in another account.
  """
  @spec start_query_by_identifiers(
          identifiers :: [String.t()],
          start_time :: non_neg_integer(),
          end_time :: non_neg_integer(),
          query :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, %{query_id: String.t()}} | {:error, term()}
  def start_query_by_identifiers([_ | _] = identifiers, start_time, end_time, query, opts \\ []) do
    if sandbox?(opts) do
      sandbox_start_query_by_identifiers_response(identifiers, start_time, end_time, query, opts)
    else
      do_start_query(%{"logGroupIdentifiers" => identifiers}, start_time, end_time, query, opts)
    end
  end

  defp do_start_query(selector, start_time, end_time, query, opts) do
    data =
      selector
      |> Map.merge(%{
        "startTime" => start_time,
        "endTime" => end_time,
        "queryString" => query
      })
      |> maybe_put("limit", opts[:limit])

    with {:ok, op} <- build_operation("StartQuery", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Fetches results for an Insights query started by `start_query/5`.

  ## Examples

      AwsSDK.Logs.get_query_results("12ab3456-12ab-123a-789e-1234567890ab")
      #=> {:ok,
      #=>  %{
      #=>    status: "Complete",
      #=>    results: [
      #=>      [
      #=>        %{field: "@timestamp", value: "2026-01-01 00:00:00.000"},
      #=>        %{field: "@message", value: "ERROR database unreachable"}
      #=>      ]
      #=>    ],
      #=>    statistics: %{records_matched: 1.0, records_scanned: 5000.0, bytes_scanned: 1.2e6}
      #=>  }}

  Each row is a list of field/value pairs, not a map -- Insights columns are
  query-defined and can repeat. `:status` is `"Scheduled"`, `"Running"`,
  `"Complete"`, `"Failed"`, `"Cancelled"` or `"Timeout"`.
  """
  @spec get_query_results(query_id :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def get_query_results(query_id, opts \\ []) when is_binary(query_id) do
    if sandbox?(opts) do
      sandbox_get_query_results_response(query_id, opts)
    else
      do_get_query_results(query_id, opts)
    end
  end

  defp do_get_query_results(query_id, opts) do
    with {:ok, op} <- build_operation("GetQueryResults", %{"queryId" => query_id}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Stops an in-flight Insights query.

  ## Examples

      AwsSDK.Logs.stop_query("12ab3456-12ab-123a-789e-1234567890ab")
      #=> {:ok, %{success: true}}

  `:success` is false when the query had already finished.
  """
  @spec stop_query(query_id :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def stop_query(query_id, opts \\ []) when is_binary(query_id) do
    if sandbox?(opts) do
      sandbox_stop_query_response(query_id, opts)
    else
      do_stop_query(query_id, opts)
    end
  end

  defp do_stop_query(query_id, opts) do
    with {:ok, op} <- build_operation("StopQuery", %{"queryId" => query_id}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @doc false
  def build_operation(action, data, opts) do
    with {:ok, config} <- Client.resolve_config(:logs, opts, &"logs.#{&1}.amazonaws.com") do
      op = %Operation{
        method: :post,
        url: Client.simple_url(config),
        headers: [
          {"content-type", @content_type},
          {"x-amz-target", "#{@target_prefix}.#{action}"}
        ],
        body: encode_body(data),
        service: @service,
        region: config.region,
        access_key_id: config.access_key_id,
        secret_access_key: config.secret_access_key,
        security_token: config.security_token,
        http: Keyword.get(opts, :http, [])
      }

      {:ok, apply_overrides(op, opts[:logs] || [])}
    end
  end

  defp encode_body(data) when map_size(data) === 0, do: "{}"
  defp encode_body(data), do: data |> :json.encode() |> IO.iodata_to_binary()

  defp decode_body(""), do: %{}

  defp decode_body(binary) when is_binary(binary) do
    :json.decode(binary)
  rescue
    _ -> binary
  end

  # AWS owns the response-body namespace and adds new fields over time.
  # `Serializer.deserialize/2`'s default is `to_existing_atom: true, strict: true`,
  # which crashes on any field whose snake-cased atom hasn't been referenced
  # elsewhere in the project. Bodies must round-trip without crashing, so
  # atom-safety is relaxed here by default. Callers can still override any of
  # these options by passing their own `opts` -- caller-supplied keys win the merge.
  @deserialize_defaults [to_existing_atom: false, strict: false]

  defp deserialize_opts(opts), do: Keyword.merge(@deserialize_defaults, opts)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # CloudWatch Logs uses camelCase (lowercase first letter) keys on the wire.
  defp camelize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {camelize(k), camelize_keys(v)} end)
  end

  defp camelize_keys(list) when is_list(list), do: Enum.map(list, &camelize_keys/1)
  defp camelize_keys(other), do: other

  defp camelize(key) when is_atom(key), do: key |> Atom.to_string() |> Recase.to_camel()
  defp camelize(key) when is_binary(key), do: Recase.to_camel(key)

  # ---------------------------------------------------------------------------
  # Sandbox delegation
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
    defdelegate sandbox_disabled?, to: AwsSDK.Logs.Sandbox

    # Log Groups
    @doc false
    defdelegate sandbox_create_log_group_response(name, opts),
      to: AwsSDK.Logs.Sandbox,
      as: :create_log_group_response

    @doc false
    defdelegate sandbox_delete_log_group_response(name, opts),
      to: AwsSDK.Logs.Sandbox,
      as: :delete_log_group_response

    @doc false
    defdelegate sandbox_describe_log_groups_response(opts),
      to: AwsSDK.Logs.Sandbox,
      as: :describe_log_groups_response

    @doc false
    defdelegate sandbox_put_retention_policy_response(name, days, opts),
      to: AwsSDK.Logs.Sandbox,
      as: :put_retention_policy_response

    @doc false
    defdelegate sandbox_delete_retention_policy_response(name, opts),
      to: AwsSDK.Logs.Sandbox,
      as: :delete_retention_policy_response

    # Log Streams
    @doc false
    defdelegate sandbox_create_log_stream_response(group, stream, opts),
      to: AwsSDK.Logs.Sandbox,
      as: :create_log_stream_response

    @doc false
    defdelegate sandbox_delete_log_stream_response(group, stream, opts),
      to: AwsSDK.Logs.Sandbox,
      as: :delete_log_stream_response

    @doc false
    defdelegate sandbox_describe_log_streams_response(group, opts),
      to: AwsSDK.Logs.Sandbox,
      as: :describe_log_streams_response

    # Log Events
    @doc false
    defdelegate sandbox_put_log_events_response(group, stream, events, opts),
      to: AwsSDK.Logs.Sandbox,
      as: :put_log_events_response

    @doc false
    defdelegate sandbox_get_log_events_response(group, stream, opts),
      to: AwsSDK.Logs.Sandbox,
      as: :get_log_events_response

    @doc false
    defdelegate sandbox_filter_log_events_response(group, opts),
      to: AwsSDK.Logs.Sandbox,
      as: :filter_log_events_response

    # Insights Queries
    @doc false
    defdelegate sandbox_start_query_response(group, start_time, end_time, query, opts),
      to: AwsSDK.Logs.Sandbox,
      as: :start_query_response

    @doc false
    defdelegate sandbox_get_query_results_response(query_id, opts),
      to: AwsSDK.Logs.Sandbox,
      as: :get_query_results_response

    @doc false
    defdelegate sandbox_stop_query_response(query_id, opts),
      to: AwsSDK.Logs.Sandbox,
      as: :stop_query_response

    @doc false
    defdelegate sandbox_start_query_by_identifiers_response(
                  identifiers,
                  start_time,
                  end_time,
                  query,
                  opts
                ),
                to: AwsSDK.Logs.Sandbox,
                as: :start_query_by_identifiers_response

    @doc false
    defdelegate sandbox_start_query_for_log_groups_response(
                  groups,
                  start_time,
                  end_time,
                  query,
                  opts
                ),
                to: AwsSDK.Logs.Sandbox,
                as: :start_query_for_log_groups_response
  else
    defp sandbox_disabled?, do: true

    defp sandbox_create_log_group_response(_, _), do: raise("sandbox not available")
    defp sandbox_delete_log_group_response(_, _), do: raise("sandbox not available")
    defp sandbox_describe_log_groups_response(_), do: raise("sandbox not available")
    defp sandbox_put_retention_policy_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_delete_retention_policy_response(_, _), do: raise("sandbox not available")
    defp sandbox_create_log_stream_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_delete_log_stream_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_describe_log_streams_response(_, _), do: raise("sandbox not available")
    defp sandbox_put_log_events_response(_, _, _, _), do: raise("sandbox not available")
    defp sandbox_get_log_events_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_filter_log_events_response(_, _), do: raise("sandbox not available")
    defp sandbox_start_query_response(_, _, _, _, _), do: raise("sandbox not available")
    defp sandbox_get_query_results_response(_, _), do: raise("sandbox not available")
    defp sandbox_stop_query_response(_, _), do: raise("sandbox not available")

    defp sandbox_start_query_by_identifiers_response(
           _identifiers,
           _start_time,
           _end_time,
           _query,
           _opts
         ),
         do: raise("sandbox not available")

    defp sandbox_start_query_for_log_groups_response(
           _groups,
           _start_time,
           _end_time,
           _query,
           _opts
         ),
         do: raise("sandbox not available")
  end

  # ---------------------------------------------------------------------------
  # Overrides / response handling
  # ---------------------------------------------------------------------------

  @override_keys [:headers, :body, :http, :url]

  defp apply_overrides(op, overrides) do
    Enum.reduce(@override_keys, op, fn key, acc ->
      case Keyword.fetch(overrides, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end
end
