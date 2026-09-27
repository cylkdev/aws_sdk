defmodule AwsSDK.EventBridge do
  @moduledoc """
  `AwsSDK.EventBridge` provides an API for Amazon EventBridge.

  This API calls the AWS EventBridge JSON 1.1 API directly over HTTP using
  `Finch` as the HTTP client, Erlang's built-in `:json` for encoding/decoding
  (OTP 27+ required), and a hand-rolled SigV4 signer. It provides consistent
  error handling, response deserialization, and sandbox support.

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

    - `:events` - A keyword list of EventBridge endpoint overrides.
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

      AwsSDK.EventBridge.Sandbox.start_link()

  ### Usage

      setup do
        AwsSDK.EventBridge.Sandbox.set_put_rule_responses([
          {"my-rule", fn -> {:ok, %{rule_arn: "arn:aws:events:us-west-1:123:rule/my-rule"}} end}
        ])
      end

      test "creates a rule" do
        assert {:ok, %{rule_arn: _}} =
                 AwsSDK.EventBridge.put_rule("my-rule",
                   event_pattern: %{"source" => ["aws.s3"]},
                   sandbox: [enabled: true]
                 )
      end
  """

  alias AwsSDK.Client
  alias AwsSDK.Operation
  alias ExUtils.Serializer

  @service "events"
  @content_type "application/x-amz-json-1.1"
  @target_prefix "AWSEvents"

  # Rule management

  @doc """
  Creates or updates an EventBridge rule.

  ## Arguments

    * `name` - The rule name (1-64 chars).
    * `opts` - Options including `:event_pattern`, `:description`, `:state`,
      `:role_arn`, `:event_bus_name`, plus shared options.

  ## Examples

      pattern = AwsSDK.EventBridge.s3_object_created_pattern("uploads-bucket")

      AwsSDK.EventBridge.put_rule("s3-uploads",
        event_pattern: pattern,
        description: "Fan out new uploads",
        state: "ENABLED"
      )
      #=> {:ok, %{rule_arn: "arn:aws:events:us-east-1:123456789012:rule/s3-uploads"}}

      # A schedule instead of a pattern.
      AwsSDK.EventBridge.put_rule("nightly", schedule_expression: "cron(0 3 * * ? *)")
      #=> {:ok, %{rule_arn: "arn:aws:events:us-east-1:123456789012:rule/nightly"}}

  Creates or updates; supply exactly one of `:event_pattern` or
  `:schedule_expression`.
  """
  @spec put_rule(name :: String.t(), opts :: keyword()) ::
          {:ok, %{rule_arn: String.t()}} | {:error, term()}
  def put_rule(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_put_rule_response(name, opts)
    else
      do_put_rule(name, opts)
    end
  end

  defp do_put_rule(name, opts) do
    data =
      %{"Name" => name}
      |> maybe_put("EventPattern", opts[:event_pattern], &encode_json/1)
      |> maybe_put("ScheduleExpression", opts[:schedule_expression])
      |> maybe_put("Description", opts[:description])
      |> maybe_put("State", opts[:state])
      |> maybe_put("RoleArn", opts[:role_arn])
      |> maybe_put("EventBusName", opts[:event_bus_name])

    with {:ok, op} <- build_operation("PutRule", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Returns details about an EventBridge rule.

  ## Examples

      AwsSDK.EventBridge.describe_rule("s3-uploads")
      #=> {:ok,
      #=>  %{
      #=>    name: "s3-uploads",
      #=>    arn: "arn:aws:events:us-east-1:123456789012:rule/s3-uploads",
      #=>    event_pattern: "{\"source\":[\"aws.s3\"],...}",
      #=>    state: "ENABLED",
      #=>    description: "Fan out new uploads",
      #=>    event_bus_name: "default"
      #=>  }}

  `:event_pattern` comes back as a JSON string, as AWS stores it.
  """
  @spec describe_rule(name :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def describe_rule(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_describe_rule_response(name, opts)
    else
      do_describe_rule(name, opts)
    end
  end

  defp do_describe_rule(name, opts) do
    data = maybe_put(%{"Name" => name}, "EventBusName", opts[:event_bus_name])

    with {:ok, op} <- build_operation("DescribeRule", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists EventBridge rules, optionally filtered by name prefix.

  ## Examples

      AwsSDK.EventBridge.list_rules(name_prefix: "s3-")
      #=> {:ok,
      #=>  %{
      #=>    rules: [
      #=>      %{
      #=>        name: "s3-uploads",
      #=>        arn: "arn:aws:events:us-east-1:123456789012:rule/s3-uploads",
      #=>        state: "ENABLED",
      #=>        description: "Fan out new uploads",
      #=>        event_bus_name: "default"
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec list_rules(opts :: keyword()) ::
          {:ok, %{rules: list(map()), next_token: String.t() | nil}} | {:error, term()}
  def list_rules(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_rules_response(opts)
    else
      do_list_rules(opts)
    end
  end

  defp do_list_rules(opts) do
    data =
      %{}
      |> maybe_put("NamePrefix", opts[:name_prefix])
      |> maybe_put("EventBusName", opts[:event_bus_name])
      |> maybe_put("Limit", opts[:limit])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <- build_operation("ListRules", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deletes an EventBridge rule. Targets must be removed first.

  ## Examples

      AwsSDK.EventBridge.delete_rule("s3-uploads")
      #=> {:ok, %{}}

  Remove the rule's targets first with `remove_targets/3`, or pass
  `force: true`.
  """
  @spec delete_rule(name :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def delete_rule(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_delete_rule_response(name, opts)
    else
      do_delete_rule(name, opts)
    end
  end

  defp do_delete_rule(name, opts) do
    data =
      %{"Name" => name}
      |> maybe_put("EventBusName", opts[:event_bus_name])
      |> maybe_put("Force", opts[:force])

    with {:ok, op} <- build_operation("DeleteRule", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # Target management

  @doc """
  Adds targets to an EventBridge rule.

  ## Arguments

    * `rule` - The rule name.
    * `targets` - List of target maps with `:id`, `:arn`, and optional `:role_arn`, `:input`, `:input_path`.
    * `opts` - Options including `:event_bus_name`, plus shared options.

  ## Examples

      AwsSDK.EventBridge.put_targets("s3-uploads", [
        %{
          id: "sqs-queue",
          arn: "arn:aws:sqs:us-east-1:123456789012:uploads"
        }
      ])
      #=> {:ok, %{failed_entry_count: 0, failed_entries: []}}

      # A partial failure reports per-target errors instead of erroring out.
      #=> {:ok,
      #=>  %{
      #=>    failed_entry_count: 1,
      #=>    failed_entries: [
      #=>      %{
      #=>        target_id: "sqs-queue",
      #=>        error_code: "AccessDeniedException",
      #=>        error_message: "EventBridge cannot assume the role"
      #=>      }
      #=>    ]
      #=>  }}

  Always check `:failed_entry_count` -- a partial failure still returns
  `{:ok, _}`.
  """
  @spec put_targets(rule :: String.t(), targets :: list(map()), opts :: keyword()) ::
          {:ok, %{failed_entry_count: integer(), failed_entries: list()}} | {:error, term()}
  def put_targets(rule, [_ | _] = targets, opts \\ []) when is_binary(rule) do
    if sandbox?(opts) do
      sandbox_put_targets_response(rule, targets, opts)
    else
      do_put_targets(rule, targets, opts)
    end
  end

  defp do_put_targets(rule, targets, opts) do
    data =
      maybe_put(
        %{"Rule" => rule, "Targets" => Enum.map(targets, &camelize_with_json(&1, "Input"))},
        "EventBusName",
        opts[:event_bus_name]
      )

    with {:ok, op} <- build_operation("PutTargets", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists targets attached to an EventBridge rule.

  ## Examples

      AwsSDK.EventBridge.list_targets_by_rule("s3-uploads")
      #=> {:ok,
      #=>  %{
      #=>    targets: [
      #=>      %{
      #=>        id: "sqs-queue",
      #=>        arn: "arn:aws:sqs:us-east-1:123456789012:uploads"
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec list_targets_by_rule(rule :: String.t(), opts :: keyword()) ::
          {:ok, %{targets: list(map()), next_token: String.t() | nil}} | {:error, term()}
  def list_targets_by_rule(rule, opts \\ []) when is_binary(rule) do
    if sandbox?(opts) do
      sandbox_list_targets_by_rule_response(rule, opts)
    else
      do_list_targets_by_rule(rule, opts)
    end
  end

  defp do_list_targets_by_rule(rule, opts) do
    data =
      %{"Rule" => rule}
      |> maybe_put("EventBusName", opts[:event_bus_name])
      |> maybe_put("Limit", opts[:limit])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <- build_operation("ListTargetsByRule", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Removes targets from an EventBridge rule.

  ## Examples

      AwsSDK.EventBridge.remove_targets("s3-uploads", ["sqs-queue"])
      #=> {:ok, %{failed_entry_count: 0, failed_entries: []}}

  Targets are removed by the `:id` given to `put_targets/3`, not by ARN.
  """
  @spec remove_targets(rule :: String.t(), ids :: list(String.t()), opts :: keyword()) ::
          {:ok, %{failed_entry_count: integer(), failed_entries: list()}} | {:error, term()}
  def remove_targets(rule, [_ | _] = ids, opts \\ []) when is_binary(rule) do
    if sandbox?(opts) do
      sandbox_remove_targets_response(rule, ids, opts)
    else
      do_remove_targets(rule, ids, opts)
    end
  end

  defp do_remove_targets(rule, ids, opts) do
    data =
      %{"Rule" => rule, "Ids" => ids}
      |> maybe_put("EventBusName", opts[:event_bus_name])
      |> maybe_put("Force", opts[:force])

    with {:ok, op} <- build_operation("RemoveTargets", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # Connection management

  @doc """
  Creates a connection that stores authentication credentials for API destinations.

  ## Arguments

    * `name` - Connection name (1-64 chars).
    * `authorization_type` - One of `"API_KEY"`, `"BASIC"`, `"OAUTH_CLIENT_CREDENTIALS"`.
    * `auth_parameters` - Map with PascalCase keys matching the AWS API
      (e.g., `%{"ApiKeyAuthParameters" => %{"ApiKeyName" => "...", "ApiKeyValue" => "..."}}`).
    * `opts` - Options including `:description`, plus shared options.

  ## Examples

      AwsSDK.EventBridge.create_connection("partner-api", "API_KEY",
        auth_parameters: %{
          "ApiKeyAuthParameters" => %{
            "ApiKeyName" => "x-api-key",
            "ApiKeyValue" => "s3cr3t"
          }
        }
      )
      #=> {:ok,
      #=>  %{
      #=>    connection_arn: "arn:aws:events:us-east-1:123456789012:connection/partner-api/aa11bb22",
      #=>    connection_state: "AUTHORIZING",
      #=>    creation_time: 1.7e9,
      #=>    last_modified_time: 1.7e9
      #=>  }}

  The secret is stored in Secrets Manager and never returned again.
  """
  @spec create_connection(
          name :: String.t(),
          authorization_type :: String.t(),
          auth_parameters :: map(),
          opts :: keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def create_connection(name, authorization_type, auth_parameters, opts \\ [])
      when is_binary(name) and is_binary(authorization_type) and is_map(auth_parameters) do
    if sandbox?(opts) do
      sandbox_create_connection_response(name, authorization_type, auth_parameters, opts)
    else
      do_create_connection(name, authorization_type, auth_parameters, opts)
    end
  end

  defp do_create_connection(name, authorization_type, auth_parameters, opts) do
    data =
      maybe_put(
        %{
          "Name" => name,
          "AuthorizationType" => authorization_type,
          "AuthParameters" => auth_parameters
        },
        "Description",
        opts[:description]
      )

    with {:ok, op} <- build_operation("CreateConnection", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Returns details about a connection.

  ## Examples

      AwsSDK.EventBridge.describe_connection("partner-api")
      #=> {:ok,
      #=>  %{
      #=>    name: "partner-api",
      #=>    connection_arn: "arn:aws:events:us-east-1:123456789012:connection/partner-api/aa11bb22",
      #=>    connection_state: "AUTHORIZED",
      #=>    authorization_type: "API_KEY",
      #=>    secret_arn: "arn:aws:secretsmanager:us-east-1:123456789012:secret:events!connection/partner-api-aa11bb22",
      #=>    auth_parameters: %{api_key_auth_parameters: %{api_key_name: "x-api-key"}},
      #=>    creation_time: 1.7e9
      #=>  }}
  """
  @spec describe_connection(name :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def describe_connection(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_describe_connection_response(name, opts)
    else
      do_describe_connection(name, opts)
    end
  end

  defp do_describe_connection(name, opts) do
    with {:ok, op} <- build_operation("DescribeConnection", %{"Name" => name}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Updates a connection's authorization parameters.

  ## Options

    * `:authorization_type` - New auth type.
    * `:auth_parameters` - New auth parameters (PascalCase map).
    * `:description` - New description.

  ## Examples

      AwsSDK.EventBridge.update_connection("partner-api",
        auth_parameters: %{
          "ApiKeyAuthParameters" => %{"ApiKeyName" => "x-api-key", "ApiKeyValue" => "rotated"}
        }
      )
      #=> {:ok,
      #=>  %{
      #=>    connection_arn: "arn:aws:events:us-east-1:123456789012:connection/partner-api/aa11bb22",
      #=>    connection_state: "AUTHORIZING",
      #=>    last_modified_time: 1.7e9
      #=>  }}
  """
  @spec update_connection(name :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def update_connection(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_update_connection_response(name, opts)
    else
      do_update_connection(name, opts)
    end
  end

  defp do_update_connection(name, opts) do
    data =
      %{"Name" => name}
      |> maybe_put("AuthorizationType", opts[:authorization_type])
      |> maybe_put("AuthParameters", opts[:auth_parameters])
      |> maybe_put("Description", opts[:description])

    with {:ok, op} <- build_operation("UpdateConnection", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deletes a connection.

  ## Examples

      AwsSDK.EventBridge.delete_connection("partner-api")
      #=> {:ok,
      #=>  %{
      #=>    connection_arn: "arn:aws:events:us-east-1:123456789012:connection/partner-api/aa11bb22",
      #=>    connection_state: "DELETING",
      #=>    last_modified_time: 1.7e9
      #=>  }}
  """
  @spec delete_connection(name :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def delete_connection(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_delete_connection_response(name, opts)
    else
      do_delete_connection(name, opts)
    end
  end

  defp do_delete_connection(name, opts) do
    with {:ok, op} <- build_operation("DeleteConnection", %{"Name" => name}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists connections, optionally filtered by name prefix or state.

  ## Examples

      AwsSDK.EventBridge.list_connections(name_prefix: "partner-")
      #=> {:ok,
      #=>  %{
      #=>    connections: [
      #=>      %{
      #=>        name: "partner-api",
      #=>        connection_arn: "arn:aws:events:us-east-1:123456789012:connection/partner-api/aa11bb22",
      #=>        connection_state: "AUTHORIZED",
      #=>        authorization_type: "API_KEY",
      #=>        creation_time: 1.7e9
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec list_connections(opts :: keyword()) ::
          {:ok, %{connections: list(map()), next_token: String.t() | nil}} | {:error, term()}
  def list_connections(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_connections_response(opts)
    else
      do_list_connections(opts)
    end
  end

  defp do_list_connections(opts) do
    data =
      %{}
      |> maybe_put("NamePrefix", opts[:name_prefix])
      |> maybe_put("ConnectionState", opts[:connection_state])
      |> maybe_put("Limit", opts[:limit])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <- build_operation("ListConnections", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # API Destination management

  @doc """
  Creates an API destination (HTTP endpoint for event delivery).

  ## Arguments

    * `name` - API destination name (1-64 chars).
    * `connection_arn` - ARN of the connection for authentication.
    * `invocation_endpoint` - Full URL of the HTTP endpoint.
    * `http_method` - HTTP method (`"POST"`, `"GET"`, `"PUT"`, etc.).
    * `opts` - Options including `:description`, `:invocation_rate_limit_per_second`, plus shared options.

  ## Examples

      AwsSDK.EventBridge.create_api_destination(
        "partner-webhook",
        "arn:aws:events:us-east-1:123456789012:connection/partner-api/aa11bb22",
        "https://partner.example.com/hooks/events",
        "POST",
        invocation_rate_limit_per_second: 10
      )
      #=> {:ok,
      #=>  %{
      #=>    api_destination_arn: "arn:aws:events:us-east-1:123456789012:api-destination/partner-webhook/cc33dd44",
      #=>    api_destination_state: "ACTIVE",
      #=>    creation_time: 1.7e9,
      #=>    last_modified_time: 1.7e9
      #=>  }}
  """
  @spec create_api_destination(
          name :: String.t(),
          connection_arn :: String.t(),
          invocation_endpoint :: String.t(),
          http_method :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def create_api_destination(name, connection_arn, invocation_endpoint, http_method, opts \\ [])
      when is_binary(name) and is_binary(connection_arn) and is_binary(invocation_endpoint) and
             is_binary(http_method) do
    if sandbox?(opts) do
      sandbox_create_api_destination_response(
        name,
        connection_arn,
        invocation_endpoint,
        http_method,
        opts
      )
    else
      do_create_api_destination(name, connection_arn, invocation_endpoint, http_method, opts)
    end
  end

  defp do_create_api_destination(name, connection_arn, invocation_endpoint, http_method, opts) do
    data =
      %{
        "Name" => name,
        "ConnectionArn" => connection_arn,
        "InvocationEndpoint" => invocation_endpoint,
        "HttpMethod" => http_method
      }
      |> maybe_put("Description", opts[:description])
      |> maybe_put("InvocationRateLimitPerSecond", opts[:invocation_rate_limit_per_second])

    with {:ok, op} <- build_operation("CreateApiDestination", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Returns details about an API destination.

  ## Examples

      AwsSDK.EventBridge.describe_api_destination("partner-webhook")
      #=> {:ok,
      #=>  %{
      #=>    name: "partner-webhook",
      #=>    api_destination_arn: "arn:aws:events:us-east-1:123456789012:api-destination/partner-webhook/cc33dd44",
      #=>    api_destination_state: "ACTIVE",
      #=>    connection_arn: "arn:aws:events:us-east-1:123456789012:connection/partner-api/aa11bb22",
      #=>    invocation_endpoint: "https://partner.example.com/hooks/events",
      #=>    http_method: "POST",
      #=>    invocation_rate_limit_per_second: 10,
      #=>    creation_time: 1.7e9
      #=>  }}
  """
  @spec describe_api_destination(name :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def describe_api_destination(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_describe_api_destination_response(name, opts)
    else
      do_describe_api_destination(name, opts)
    end
  end

  defp do_describe_api_destination(name, opts) do
    with {:ok, op} <- build_operation("DescribeApiDestination", %{"Name" => name}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Updates an API destination.

  ## Options

    * `:connection_arn` - New connection ARN.
    * `:invocation_endpoint` - New endpoint URL.
    * `:http_method` - New HTTP method.
    * `:description` - New description.
    * `:invocation_rate_limit_per_second` - New rate limit.

  ## Examples

      AwsSDK.EventBridge.update_api_destination("partner-webhook",
        invocation_rate_limit_per_second: 50
      )
      #=> {:ok,
      #=>  %{
      #=>    api_destination_arn: "arn:aws:events:us-east-1:123456789012:api-destination/partner-webhook/cc33dd44",
      #=>    api_destination_state: "ACTIVE",
      #=>    last_modified_time: 1.7e9
      #=>  }}
  """
  @spec update_api_destination(name :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def update_api_destination(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_update_api_destination_response(name, opts)
    else
      do_update_api_destination(name, opts)
    end
  end

  defp do_update_api_destination(name, opts) do
    data =
      %{"Name" => name}
      |> maybe_put("ConnectionArn", opts[:connection_arn])
      |> maybe_put("InvocationEndpoint", opts[:invocation_endpoint])
      |> maybe_put("HttpMethod", opts[:http_method])
      |> maybe_put("Description", opts[:description])
      |> maybe_put("InvocationRateLimitPerSecond", opts[:invocation_rate_limit_per_second])

    with {:ok, op} <- build_operation("UpdateApiDestination", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deletes an API destination.

  ## Examples

      AwsSDK.EventBridge.delete_api_destination("partner-webhook")
      #=> {:ok, %{}}
  """
  @spec delete_api_destination(name :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def delete_api_destination(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_delete_api_destination_response(name, opts)
    else
      do_delete_api_destination(name, opts)
    end
  end

  defp do_delete_api_destination(name, opts) do
    with {:ok, op} <- build_operation("DeleteApiDestination", %{"Name" => name}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists API destinations, optionally filtered by name prefix or connection.

  ## Examples

      AwsSDK.EventBridge.list_api_destinations(name_prefix: "partner-")
      #=> {:ok,
      #=>  %{
      #=>    api_destinations: [
      #=>      %{
      #=>        name: "partner-webhook",
      #=>        api_destination_arn: "arn:aws:events:us-east-1:123456789012:api-destination/partner-webhook/cc33dd44",
      #=>        api_destination_state: "ACTIVE",
      #=>        connection_arn: "arn:aws:events:us-east-1:123456789012:connection/partner-api/aa11bb22",
      #=>        http_method: "POST"
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec list_api_destinations(opts :: keyword()) ::
          {:ok, %{api_destinations: list(map()), next_token: String.t() | nil}} | {:error, term()}
  def list_api_destinations(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_api_destinations_response(opts)
    else
      do_list_api_destinations(opts)
    end
  end

  defp do_list_api_destinations(opts) do
    data =
      %{}
      |> maybe_put("NamePrefix", opts[:name_prefix])
      |> maybe_put("ConnectionArn", opts[:connection_arn])
      |> maybe_put("Limit", opts[:limit])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <- build_operation("ListApiDestinations", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # Event Bus management

  @doc """
  Creates a custom event bus.

  ## Examples

      AwsSDK.EventBridge.create_event_bus("app-bus")
      #=> {:ok, %{event_bus_arn: "arn:aws:events:us-east-1:123456789012:event-bus/app-bus"}}
  """
  @spec create_event_bus(name :: String.t(), opts :: keyword()) ::
          {:ok, %{event_bus_arn: String.t()}} | {:error, term()}
  def create_event_bus(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_create_event_bus_response(name, opts)
    else
      do_create_event_bus(name, opts)
    end
  end

  defp do_create_event_bus(name, opts) do
    data = maybe_put(%{"Name" => name}, "EventSourceName", opts[:event_source_name])

    with {:ok, op} <- build_operation("CreateEventBus", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Returns details about an event bus.

  ## Examples

      AwsSDK.EventBridge.describe_event_bus(name: "app-bus")
      #=> {:ok,
      #=>  %{
      #=>    name: "app-bus",
      #=>    arn: "arn:aws:events:us-east-1:123456789012:event-bus/app-bus",
      #=>    policy: "{\"Version\":\"2012-10-17\",...}"
      #=>  }}

  Omit `:name` to describe the account's `default` bus.
  """
  @spec describe_event_bus(name :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def describe_event_bus(name \\ "default", opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_describe_event_bus_response(name, opts)
    else
      do_describe_event_bus(name, opts)
    end
  end

  defp do_describe_event_bus(name, opts) do
    with {:ok, op} <- build_operation("DescribeEventBus", %{"Name" => name}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deletes a custom event bus. Cannot delete the default bus.

  ## Examples

      AwsSDK.EventBridge.delete_event_bus("app-bus")
      #=> {:ok, %{}}

  The `default` bus cannot be deleted.
  """
  @spec delete_event_bus(name :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def delete_event_bus(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_delete_event_bus_response(name, opts)
    else
      do_delete_event_bus(name, opts)
    end
  end

  defp do_delete_event_bus(name, opts) do
    with {:ok, op} <- build_operation("DeleteEventBus", %{"Name" => name}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists event buses, optionally filtered by name prefix.

  ## Examples

      AwsSDK.EventBridge.list_event_buses()
      #=> {:ok,
      #=>  %{
      #=>    event_buses: [
      #=>      %{name: "default", arn: "arn:aws:events:us-east-1:123456789012:event-bus/default"},
      #=>      %{name: "app-bus", arn: "arn:aws:events:us-east-1:123456789012:event-bus/app-bus"}
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec list_event_buses(opts :: keyword()) ::
          {:ok, %{event_buses: list(map()), next_token: String.t() | nil}} | {:error, term()}
  def list_event_buses(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_event_buses_response(opts)
    else
      do_list_event_buses(opts)
    end
  end

  defp do_list_event_buses(opts) do
    data =
      %{}
      |> maybe_put("NamePrefix", opts[:name_prefix])
      |> maybe_put("Limit", opts[:limit])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <- build_operation("ListEventBuses", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # Event publishing

  @doc """
  Publishes events to an event bus.

  ## Arguments

    * `entries` - List of event maps. Each entry should have `:source`, `:detail_type`,
      `:detail` (JSON string), and optionally `:event_bus_name`, `:time`, `:resources`.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.EventBridge.put_events([
        %{
          source: "com.example.app",
          detail_type: "OrderPlaced",
          detail: %{"order_id" => "abc123", "total" => 42},
          event_bus_name: "app-bus"
        }
      ])
      #=> {:ok,
      #=>  %{
      #=>    failed_entry_count: 0,
      #=>    entries: [%{event_id: "12345678-1234-1234-1234-123456789012"}]
      #=>  }}

      # A rejected entry carries an error in place of an event ID.
      #=> {:ok,
      #=>  %{
      #=>    failed_entry_count: 1,
      #=>    entries: [
      #=>      %{error_code: "NotAuthorizedForSourceException", error_message: "..."}
      #=>    ]
      #=>  }}

  Entries stay in order, so `:entries` lines up positionally with what you
  sent. Check `:failed_entry_count` -- a partial failure still returns
  `{:ok, _}`.
  """
  @spec put_events(entries :: list(map()), opts :: keyword()) ::
          {:ok, %{entries: list(map()), failed_entry_count: integer()}} | {:error, term()}
  def put_events([_ | _] = entries, opts \\ []) do
    if sandbox?(opts) do
      sandbox_put_events_response(entries, opts)
    else
      do_put_events(entries, opts)
    end
  end

  defp do_put_events(entries, opts) do
    data = %{"Entries" => Enum.map(entries, &camelize_with_json(&1, "Detail"))}

    with {:ok, op} <- build_operation("PutEvents", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # Rule control

  @doc """
  Enables a disabled rule.

  ## Examples

      AwsSDK.EventBridge.enable_rule("s3-uploads")
      #=> {:ok, %{}}
  """
  @spec enable_rule(name :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def enable_rule(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_enable_rule_response(name, opts)
    else
      do_enable_rule(name, opts)
    end
  end

  defp do_enable_rule(name, opts) do
    data = maybe_put(%{"Name" => name}, "EventBusName", opts[:event_bus_name])

    with {:ok, op} <- build_operation("EnableRule", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Disables an enabled rule.

  ## Examples

      AwsSDK.EventBridge.disable_rule("s3-uploads")
      #=> {:ok, %{}}

  The rule and its targets are kept; it just stops matching.
  """
  @spec disable_rule(name :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def disable_rule(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_disable_rule_response(name, opts)
    else
      do_disable_rule(name, opts)
    end
  end

  defp do_disable_rule(name, opts) do
    data = maybe_put(%{"Name" => name}, "EventBusName", opts[:event_bus_name])

    with {:ok, op} <- build_operation("DisableRule", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # Pattern helpers

  @doc """
  Builds an EventBridge event pattern for S3 object creation events.

  ## Examples

      iex> AwsSDK.EventBridge.s3_object_created_pattern("my-bucket")
      %{"source" => ["aws.s3"], "detail-type" => ["Object Created"], "detail" => %{"bucket" => %{"name" => ["my-bucket"]}}}

  ## Examples

      AwsSDK.EventBridge.s3_object_created_pattern("uploads-bucket")
      #=> %{
      #=>   "source" => ["aws.s3"],
      #=>   "detail-type" => ["Object Created"],
      #=>   "detail" => %{"bucket" => %{"name" => ["uploads-bucket"]}}
      #=> }

  Pass the result straight to `put_rule/2`:

      AwsSDK.EventBridge.put_rule("s3-uploads",
        event_pattern: AwsSDK.EventBridge.s3_object_created_pattern("uploads-bucket")
      )

  Requires EventBridge notifications to be enabled on the bucket; see
  `AwsSDK.S3.enable_event_bridge/2`.
  """
  @spec s3_object_created_pattern(bucket :: String.t()) :: map()
  def s3_object_created_pattern(bucket) do
    s3_event_pattern("Object Created", bucket)
  end

  @doc """
  Builds an EventBridge event pattern for S3 object deletion events.

  ## Examples

      iex> AwsSDK.EventBridge.s3_object_deleted_pattern("my-bucket")
      %{"source" => ["aws.s3"], "detail-type" => ["Object Deleted"], "detail" => %{"bucket" => %{"name" => ["my-bucket"]}}}

  ## Examples

      AwsSDK.EventBridge.s3_object_deleted_pattern("uploads-bucket")
      #=> %{
      #=>   "source" => ["aws.s3"],
      #=>   "detail-type" => ["Object Deleted"],
      #=>   "detail" => %{"bucket" => %{"name" => ["uploads-bucket"]}}
      #=> }
  """
  @spec s3_object_deleted_pattern(bucket :: String.t()) :: map()
  def s3_object_deleted_pattern(bucket) do
    s3_event_pattern("Object Deleted", bucket)
  end

  @doc """
  Builds an EventBridge event pattern matching all S3 events for a bucket.

  Unlike `s3_object_created_pattern/1` and `s3_object_deleted_pattern/1`, this matches
  every S3 event type (created, deleted, restore, replication, etc.).

  ## Examples

      iex> AwsSDK.EventBridge.s3_all_events_pattern("my-bucket")
      %{"source" => ["aws.s3"], "detail" => %{"bucket" => %{"name" => ["my-bucket"]}}}

  ## Examples

      AwsSDK.EventBridge.s3_all_events_pattern("uploads-bucket")
      #=> %{
      #=>   "source" => ["aws.s3"],
      #=>   "detail" => %{"bucket" => %{"name" => ["uploads-bucket"]}}
      #=> }

  No `"detail-type"` key at all, which is what makes it match every S3 event
  for the bucket.
  """
  @spec s3_all_events_pattern(bucket :: String.t()) :: map()
  def s3_all_events_pattern(bucket) do
    %{
      "source" => ["aws.s3"],
      "detail" => %{
        "bucket" => %{
          "name" => [bucket]
        }
      }
    }
  end

  @doc """
  Builds an EventBridge event pattern for any S3 event type.

  ## Examples

      iex> AwsSDK.EventBridge.s3_event_pattern("Object Deleted", "my-bucket")
      %{"source" => ["aws.s3"], "detail-type" => ["Object Deleted"], "detail" => %{"bucket" => %{"name" => ["my-bucket"]}}}

  ## Examples

      AwsSDK.EventBridge.s3_event_pattern("Object Restore Completed", "uploads-bucket")
      #=> %{
      #=>   "source" => ["aws.s3"],
      #=>   "detail-type" => ["Object Restore Completed"],
      #=>   "detail" => %{"bucket" => %{"name" => ["uploads-bucket"]}}
      #=> }

  Note the argument order: the detail type comes first, the bucket second.
  Use this for event types the named helpers above do not cover.
  """
  @spec s3_event_pattern(detail_type :: String.t(), bucket :: String.t()) :: map()
  def s3_event_pattern(detail_type, bucket) do
    %{
      "source" => ["aws.s3"],
      "detail-type" => [detail_type],
      "detail" => %{
        "bucket" => %{
          "name" => [bucket]
        }
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @doc false
  def build_operation(action, data, opts) do
    with {:ok, config} <-
           Client.resolve_config(:events, opts, &"events.#{&1}.amazonaws.com") do
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

      {:ok, apply_overrides(op, opts[:events] || [])}
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

  # Without the nil clause the transform ran on `nil`, and `:json.encode(nil)`
  # yields the literal string "nil" -- so every rule created without an event
  # pattern sent `"EventPattern": "nil"` and AWS rejected it with
  # InvalidEventPatternException.
  defp maybe_put(map, _key, nil, _transform), do: map
  defp maybe_put(map, key, value, transform), do: Map.put(map, key, transform.(value))

  # `PutEvents` entries carry `Detail` and `PutTargets` targets carry `Input`;
  # AWS documents both as a String of serialized JSON. Recursing into them
  # would emit a JSON object instead of a string *and* PascalCase the caller's
  # own payload keys, silently corrupting the event. Serialize instead.
  defp camelize_with_json(map, json_key) when is_map(map) do
    {json_pairs, others} = Enum.split_with(map, fn {k, _} -> camelize(k) == json_key end)

    camelized = Map.new(others, fn {k, v} -> {camelize(k), camelize_keys(v)} end)

    case json_pairs do
      [{_, value}] -> Map.put(camelized, json_key, encode_json(value))
      [] -> camelized
    end
  end

  defp camelize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {camelize(k), camelize_keys(v)} end)
  end

  defp camelize_keys(list) when is_list(list), do: Enum.map(list, &camelize_keys/1)
  defp camelize_keys(other), do: other

  defp camelize(key) when is_atom(key), do: key |> Atom.to_string() |> Recase.to_pascal()
  defp camelize(key) when is_binary(key), do: Recase.to_pascal(key)

  # `EventPattern` is documented as a String holding serialized JSON, so a
  # caller may reasonably pass either a map or an already-serialized string.
  # Encoding a string again produces a JSON string of a JSON string, which AWS
  # rejects.
  defp encode_json(value) when is_binary(value), do: value
  defp encode_json(value), do: value |> :json.encode() |> IO.iodata_to_binary()

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
    defdelegate sandbox_disabled?, to: AwsSDK.EventBridge.Sandbox

    # Rule management
    @doc false
    defdelegate sandbox_put_rule_response(name, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :put_rule_response

    @doc false
    defdelegate sandbox_describe_rule_response(name, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :describe_rule_response

    @doc false
    defdelegate sandbox_list_rules_response(opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :list_rules_response

    @doc false
    defdelegate sandbox_delete_rule_response(name, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :delete_rule_response

    # Target management
    @doc false
    defdelegate sandbox_put_targets_response(rule, targets, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :put_targets_response

    @doc false
    defdelegate sandbox_list_targets_by_rule_response(rule, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :list_targets_by_rule_response

    @doc false
    defdelegate sandbox_remove_targets_response(rule, ids, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :remove_targets_response

    # Connection management
    @doc false
    defdelegate sandbox_create_connection_response(name, auth_type, auth_params, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :create_connection_response

    @doc false
    defdelegate sandbox_describe_connection_response(name, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :describe_connection_response

    @doc false
    defdelegate sandbox_update_connection_response(name, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :update_connection_response

    @doc false
    defdelegate sandbox_delete_connection_response(name, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :delete_connection_response

    @doc false
    defdelegate sandbox_list_connections_response(opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :list_connections_response

    # API Destination management
    @doc false
    defdelegate sandbox_create_api_destination_response(name, conn_arn, endpoint, method, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :create_api_destination_response

    @doc false
    defdelegate sandbox_describe_api_destination_response(name, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :describe_api_destination_response

    @doc false
    defdelegate sandbox_update_api_destination_response(name, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :update_api_destination_response

    @doc false
    defdelegate sandbox_delete_api_destination_response(name, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :delete_api_destination_response

    @doc false
    defdelegate sandbox_list_api_destinations_response(opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :list_api_destinations_response

    # Event Bus management
    @doc false
    defdelegate sandbox_create_event_bus_response(name, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :create_event_bus_response

    @doc false
    defdelegate sandbox_describe_event_bus_response(name, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :describe_event_bus_response

    @doc false
    defdelegate sandbox_delete_event_bus_response(name, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :delete_event_bus_response

    @doc false
    defdelegate sandbox_list_event_buses_response(opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :list_event_buses_response

    # Events
    @doc false
    defdelegate sandbox_put_events_response(entries, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :put_events_response

    # Rule control
    @doc false
    defdelegate sandbox_enable_rule_response(name, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :enable_rule_response

    @doc false
    defdelegate sandbox_disable_rule_response(name, opts),
      to: AwsSDK.EventBridge.Sandbox,
      as: :disable_rule_response
  else
    defp sandbox_disabled?, do: true

    defp sandbox_put_rule_response(_, _), do: raise("sandbox not available")
    defp sandbox_describe_rule_response(_, _), do: raise("sandbox not available")
    defp sandbox_list_rules_response(_), do: raise("sandbox not available")
    defp sandbox_delete_rule_response(_, _), do: raise("sandbox not available")
    defp sandbox_put_targets_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_list_targets_by_rule_response(_, _), do: raise("sandbox not available")
    defp sandbox_remove_targets_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_create_connection_response(_, _, _, _), do: raise("sandbox not available")
    defp sandbox_describe_connection_response(_, _), do: raise("sandbox not available")
    defp sandbox_update_connection_response(_, _), do: raise("sandbox not available")
    defp sandbox_delete_connection_response(_, _), do: raise("sandbox not available")
    defp sandbox_list_connections_response(_), do: raise("sandbox not available")

    defp sandbox_create_api_destination_response(_, _, _, _, _),
      do: raise("sandbox not available")

    defp sandbox_describe_api_destination_response(_, _), do: raise("sandbox not available")
    defp sandbox_update_api_destination_response(_, _), do: raise("sandbox not available")
    defp sandbox_delete_api_destination_response(_, _), do: raise("sandbox not available")
    defp sandbox_list_api_destinations_response(_), do: raise("sandbox not available")
    defp sandbox_create_event_bus_response(_, _), do: raise("sandbox not available")
    defp sandbox_describe_event_bus_response(_, _), do: raise("sandbox not available")
    defp sandbox_delete_event_bus_response(_, _), do: raise("sandbox not available")
    defp sandbox_list_event_buses_response(_), do: raise("sandbox not available")
    defp sandbox_put_events_response(_, _), do: raise("sandbox not available")
    defp sandbox_enable_rule_response(_, _), do: raise("sandbox not available")
    defp sandbox_disable_rule_response(_, _), do: raise("sandbox not available")
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
