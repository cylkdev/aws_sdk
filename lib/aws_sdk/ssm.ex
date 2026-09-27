defmodule AwsSDK.SSM do
  @moduledoc """
  `AwsSDK.SSM` provides an API for AWS Systems Manager.

  This API calls the AWS Systems Manager JSON 1.1 API directly over HTTP
  using `Finch` as the HTTP client, Erlang's built-in `:json` for
  encoding/decoding (OTP 27+ required), and a hand-rolled SigV4 signer.
  It provides consistent error handling, response deserialization, and
  sandbox support.

  The initial surface covers Parameter Store. See the botocore service
  model for the authoritative API reference:
  <https://github.com/boto/botocore/blob/master/botocore/data/ssm/2014-11-06/service-2.json>

  SSM uses PascalCase keys on the wire (e.g. `Name`, `WithDecryption`,
  `Parameters`). Response bodies are deserialized to snake_case atom-keyed
  maps via `ExUtils.Serializer`.

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

    - `:ssm` - A keyword list of Systems Manager endpoint overrides.
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

      AwsSDK.SSM.Sandbox.start_link()

  ### Usage

      setup do
        AwsSDK.SSM.Sandbox.set_get_parameter_responses([
          {"/app/db/host",
           fn -> {:ok, %{parameter: %{name: "/app/db/host", value: "db.internal"}}} end}
        ])
      end

      test "reads a parameter" do
        assert {:ok, %{parameter: %{value: "db.internal"}}} =
                 AwsSDK.SSM.get_parameter("/app/db/host",
                   sandbox: [enabled: true]
                 )
      end
  """

  alias AwsSDK.Client
  alias AwsSDK.Operation
  alias ExUtils.Serializer

  @service "ssm"
  @content_type "application/x-amz-json-1.1"
  @target_prefix "AmazonSSM"

  # ---------------------------------------------------------------------------
  # Parameter Store
  # ---------------------------------------------------------------------------

  @doc """
  Returns information about a single parameter from Parameter Store.

  ## Arguments

    * `name` - The fully qualified parameter name (e.g. `"/app/db/host"`),
      or `"name:version"` / `"name:label"` to pin a specific version or label.
    * `opts` - Options including `:with_decryption`, plus shared options.

  ## Examples

      AwsSDK.SSM.get_parameter("/app/prod/db-url")
      #=> {:ok,
      #=>  %{
      #=>    parameter: %{
      #=>      name: "/app/prod/db-url",
      #=>      type: "String",
      #=>      value: "postgres://db.internal:5432/app",
      #=>      version: 3,
      #=>      last_modified_date: 1.7e9,
      #=>      arn: "arn:aws:ssm:us-east-1:123456789012:parameter/app/prod/db-url",
      #=>      data_type: "text"
      #=>    }
      #=>  }}

      # SecureString values come back encrypted unless you ask otherwise.
      AwsSDK.SSM.get_parameter("/app/prod/db-password", with_decryption: true)
      #=> {:ok, %{parameter: %{type: "SecureString", value: "s3cr3t"}}}
  """
  @spec get_parameter(name :: String.t(), opts :: keyword()) ::
          {:ok, %{parameter: map()}} | {:error, term()}
  def get_parameter(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_get_parameter_response(name, opts)
    else
      do_get_parameter(name, opts)
    end
  end

  defp do_get_parameter(name, opts) do
    data =
      %{"Name" => name}
      |> maybe_put("WithDecryption", opts[:with_decryption])

    with {:ok, op} <- build_operation("GetParameter", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Returns information about multiple parameters in a single call.

  ## Arguments

    * `names` - A list of 1-10 parameter names.
    * `opts` - Options including `:with_decryption`, plus shared options.

  ## Examples

      AwsSDK.SSM.get_parameters(["/app/prod/db-url", "/app/prod/missing"])
      #=> {:ok,
      #=>  %{
      #=>    parameters: [
      #=>      %{name: "/app/prod/db-url", type: "String", value: "postgres://...", version: 3}
      #=>    ],
      #=>    invalid_parameters: ["/app/prod/missing"]
      #=>  }}

  Names AWS could not resolve come back in `:invalid_parameters` rather than
  as an error, so check it before using the result.
  """
  @spec get_parameters(names :: [String.t()], opts :: keyword()) ::
          {:ok, %{parameters: [map()], invalid_parameters: [String.t()]}} | {:error, term()}
  def get_parameters([_ | _] = names, opts \\ []) do
    if sandbox?(opts) do
      sandbox_get_parameters_response(names, opts)
    else
      do_get_parameters(names, opts)
    end
  end

  defp do_get_parameters(names, opts) do
    data =
      %{"Names" => names}
      |> maybe_put("WithDecryption", opts[:with_decryption])

    with {:ok, op} <- build_operation("GetParameters", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Returns parameters in a hierarchy by path prefix.

  ## Arguments

    * `path` - The hierarchy prefix (e.g. `"/app/"`). Must begin with `/`.
    * `opts` - Options:
      * `:recursive` - Boolean; descend into sub-paths.
      * `:with_decryption` - Boolean; return decrypted SecureString values.
      * `:parameter_filters` - List of filter maps with PascalCase keys
        (e.g. `[%{"Key" => "Type", "Values" => ["String"]}]`).
      * `:max_results` - Integer page size.
      * `:next_token` - Pagination token from a prior response.

  ## Examples

      AwsSDK.SSM.get_parameters_by_path("/app/prod/", recursive: true, with_decryption: true)
      #=> {:ok,
      #=>  %{
      #=>    parameters: [
      #=>      %{name: "/app/prod/db-url", type: "String", value: "postgres://...", version: 3},
      #=>      %{name: "/app/prod/db-password", type: "SecureString", value: "s3cr3t", version: 1}
      #=>    ],
      #=>    next_token: nil
      #=>  }}

  Without `recursive: true` only parameters directly under the path are
  returned, not those in sub-paths.
  """
  @spec get_parameters_by_path(path :: String.t(), opts :: keyword()) ::
          {:ok, %{parameters: [map()], next_token: String.t() | nil}} | {:error, term()}
  def get_parameters_by_path(path, opts \\ []) when is_binary(path) do
    if sandbox?(opts) do
      sandbox_get_parameters_by_path_response(path, opts)
    else
      do_get_parameters_by_path(path, opts)
    end
  end

  defp do_get_parameters_by_path(path, opts) do
    data =
      %{"Path" => path}
      |> maybe_put("Recursive", opts[:recursive])
      |> maybe_put("WithDecryption", opts[:with_decryption])
      |> maybe_put("ParameterFilters", opts[:parameter_filters])
      |> maybe_put("MaxResults", opts[:max_results])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <- build_operation("GetParametersByPath", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Creates or updates a parameter in Parameter Store.

  ## Arguments

    * `name` - The fully qualified parameter name (e.g. `"/app/db/host"`).
    * `value` - The parameter value.
    * `opts` - Options:
      * `:type` - `"String"` (default if not provided to AWS),
        `"StringList"`, or `"SecureString"`. Required on first write.
      * `:description` - String description.
      * `:key_id` - KMS key ARN or alias (required for SecureString unless
        the AWS-managed `alias/aws/ssm` is used).
      * `:overwrite` - Boolean; allow updating an existing parameter.
      * `:allowed_pattern` - Regex pattern the value must match.
      * `:tags` - List of `%{"Key" => k, "Value" => v}` maps.
      * `:tier` - `"Standard"`, `"Advanced"`, or `"Intelligent-Tiering"`.
      * `:policies` - JSON-encoded policy string.
      * `:data_type` - `"text"` or `"aws:ec2:image"` for AMI parameters.

  ## Examples

      AwsSDK.SSM.put_parameter("/app/prod/db-url", "postgres://db.internal:5432/app",
        type: "String",
        overwrite: true
      )
      #=> {:ok, %{version: 4, tier: "Standard"}}

      AwsSDK.SSM.put_parameter("/app/prod/db-password", "s3cr3t",
        type: "SecureString",
        key_id: "alias/aws/ssm"
      )
      #=> {:ok, %{version: 1, tier: "Standard"}}

  Without `overwrite: true` AWS rejects a write to an existing name.
  """
  @spec put_parameter(name :: String.t(), value :: String.t(), opts :: keyword()) ::
          {:ok, %{version: integer(), tier: String.t()}} | {:error, term()}
  def put_parameter(name, value, opts \\ []) when is_binary(name) and is_binary(value) do
    if sandbox?(opts) do
      sandbox_put_parameter_response(name, value, opts)
    else
      do_put_parameter(name, value, opts)
    end
  end

  defp do_put_parameter(name, value, opts) do
    data =
      %{"Name" => name, "Value" => value}
      |> maybe_put("Type", opts[:type])
      |> maybe_put("Description", opts[:description])
      |> maybe_put("KeyId", opts[:key_id])
      |> maybe_put("Overwrite", opts[:overwrite])
      |> maybe_put("AllowedPattern", opts[:allowed_pattern])
      |> maybe_put("Tags", opts[:tags])
      |> maybe_put("Tier", opts[:tier])
      |> maybe_put("Policies", opts[:policies])
      |> maybe_put("DataType", opts[:data_type])

    with {:ok, op} <- build_operation("PutParameter", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deletes a single parameter.

  ## Examples

      AwsSDK.SSM.delete_parameter("/app/prod/db-url")
      #=> {:ok, %{}}
  """
  @spec delete_parameter(name :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def delete_parameter(name, opts \\ []) when is_binary(name) do
    if sandbox?(opts) do
      sandbox_delete_parameter_response(name, opts)
    else
      do_delete_parameter(name, opts)
    end
  end

  defp do_delete_parameter(name, opts) do
    with {:ok, op} <- build_operation("DeleteParameter", %{"Name" => name}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deletes a batch of parameters (1-10 names per call).

  ## Examples

      AwsSDK.SSM.delete_parameters(["/app/prod/db-url", "/app/prod/missing"])
      #=> {:ok,
      #=>  %{
      #=>    deleted_parameters: ["/app/prod/db-url"],
      #=>    invalid_parameters: ["/app/prod/missing"]
      #=>  }}
  """
  @spec delete_parameters(names :: [String.t()], opts :: keyword()) ::
          {:ok, %{deleted_parameters: [String.t()], invalid_parameters: [String.t()]}}
          | {:error, term()}
  def delete_parameters([_ | _] = names, opts \\ []) do
    if sandbox?(opts) do
      sandbox_delete_parameters_response(names, opts)
    else
      do_delete_parameters(names, opts)
    end
  end

  defp do_delete_parameters(names, opts) do
    with {:ok, op} <- build_operation("DeleteParameters", %{"Names" => names}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists parameter metadata (no values). Useful for browsing or auditing.

  ## Options

    * `:filters` - Legacy `ParametersFilter` list of `%{"Key" => k, "Values" => vs}`.
    * `:parameter_filters` - Preferred `ParameterStringFilter` list.
    * `:max_results` - Integer page size.
    * `:next_token` - Pagination token.
    * `:shared` - Boolean; include parameters shared from other accounts.

  ## Examples

      AwsSDK.SSM.describe_parameters(max_results: 50)
      #=> {:ok,
      #=>  %{
      #=>    parameters: [
      #=>      %{
      #=>        name: "/app/prod/db-url",
      #=>        type: "String",
      #=>        version: 3,
      #=>        last_modified_date: 1.7e9,
      #=>        last_modified_user: "arn:aws:iam::123456789012:user/deploy",
      #=>        tier: "Standard",
      #=>        data_type: "text"
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}

  Metadata only -- no `:value`. Use `get_parameter/2` to read a value.
  """
  @spec describe_parameters(opts :: keyword()) ::
          {:ok, %{parameters: [map()], next_token: String.t() | nil}} | {:error, term()}
  def describe_parameters(opts \\ []) do
    if sandbox?(opts) do
      sandbox_describe_parameters_response(opts)
    else
      do_describe_parameters(opts)
    end
  end

  defp do_describe_parameters(opts) do
    data =
      %{}
      |> maybe_put("Filters", opts[:filters])
      |> maybe_put("ParameterFilters", opts[:parameter_filters])
      |> maybe_put("MaxResults", opts[:max_results])
      |> maybe_put("NextToken", opts[:next_token])
      |> maybe_put("Shared", opts[:shared])

    with {:ok, op} <- build_operation("DescribeParameters", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Managed instances
  # ---------------------------------------------------------------------------

  @doc """
  Describes one or more of your managed nodes, including information about
  operating system platform, SSM Agent version, association status, and IP
  address. AWS returns one entry per managed node.

  ## Options

    * `:instance_information_filter_list` - Legacy
      `InstanceInformationFilterList` of `%{"key" => k, "valueSet" => vs}`.
    * `:filters` - Preferred `InstanceInformationStringFilterList` of
      `%{"Key" => k, "Values" => vs}`.
    * `:max_results` - Integer page size (5-50).
    * `:next_token` - Pagination token from a prior response.

  ## Examples

      AwsSDK.SSM.describe_instance_information(max_results: 50)
      #=> {:ok,
      #=>  %{
      #=>    instance_information_list: [
      #=>      %{
      #=>        instance_id: "i-1234567890abcdef0",
      #=>        ping_status: "Online",
      #=>        last_ping_date_time: 1.7e9,
      #=>        agent_version: "3.3.1611.0",
      #=>        platform_type: "Linux",
      #=>        platform_name: "Amazon Linux",
      #=>        platform_version: "2023",
      #=>        ip_address: "10.0.1.5",
      #=>        computer_name: "ip-10-0-1-5.ec2.internal",
      #=>        resource_type: "EC2Instance"
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}

  Only instances running the SSM agent and registered with Systems Manager
  appear here.
  """
  @spec describe_instance_information(opts :: keyword()) ::
          {:ok, %{instance_information_list: [map()], next_token: String.t() | nil}}
          | {:error, term()}
  def describe_instance_information(opts \\ []) do
    if sandbox?(opts) do
      sandbox_describe_instance_information_response(opts)
    else
      do_describe_instance_information(opts)
    end
  end

  defp do_describe_instance_information(opts) do
    data =
      %{}
      |> maybe_put("InstanceInformationFilterList", opts[:instance_information_filter_list])
      |> maybe_put("Filters", opts[:filters])
      |> maybe_put("MaxResults", opts[:max_results])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <- build_operation("DescribeInstanceInformation", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Run Command
  # ---------------------------------------------------------------------------

  @doc """
  Runs a command on the specified managed nodes.

  ## Arguments

    * `instance_ids` - A list of 1-50 managed node IDs.
    * `document_name` - The SSM document to run (e.g. `"AWS-RunShellScript"`).
    * `opts` - Options:
      * `:parameters` - Map of document parameters, e.g.
        `%{"commands" => ["uptime"]}`.
      * `:comment` - User-specified information about the command.
      * `:timeout_seconds` - Seconds to wait for a node to begin running
        the command (30-2592000).
      * `:document_version` - Document version (`"$DEFAULT"`, `"$LATEST"`,
        or a version number string).
      * `:output_s3_bucket_name`, `:output_s3_key_prefix` - Where to store
        full command output.
      * `:cloud_watch_output_config` - Map with PascalCase keys, e.g.
        `%{"CloudWatchOutputEnabled" => true}`.
      * `:max_concurrency`, `:max_errors` - Rate controls.
      * `:service_role_arn`, `:notification_config` - SNS notifications.

  ## Examples

      AwsSDK.SSM.send_command(["i-1234567890abcdef0"], "AWS-RunShellScript",
        parameters: %{"commands" => ["systemctl restart app"]}
      )
      #=> {:ok,
      #=>  %{
      #=>    command: %{
      #=>      command_id: "0831e1a8-4c47-4c74-8f2a-EXAMPLE",
      #=>      document_name: "AWS-RunShellScript",
      #=>      instance_ids: ["i-1234567890abcdef0"],
      #=>      status: "Pending",
      #=>      status_details: "Pending",
      #=>      requested_date_time: 1.7e9,
      #=>      expires_after: 1.7e9,
      #=>      parameters: %{commands: ["systemctl restart app"]},
      #=>      output_s3_bucket_name: "",
      #=>      output_s3_key_prefix: ""
      #=>    }
      #=>  }}

  Poll the result with `get_command_invocation/3` using `:command_id`.
  To target by tags or resource groups instead of explicit instance IDs,
  use `send_command_by_targets/3`.
  """
  @spec send_command(instance_ids :: [String.t()], document_name :: String.t(), opts :: keyword()) ::
          {:ok, %{command: map()}} | {:error, term()}
  def send_command([_ | _] = instance_ids, document_name, opts \\ [])
      when is_binary(document_name) do
    if sandbox?(opts) do
      sandbox_send_command_response(instance_ids, document_name, opts)
    else
      do_send_command(instance_ids, document_name, opts)
    end
  end

  defp do_send_command(instance_ids, document_name, opts) do
    data =
      %{"InstanceIds" => instance_ids, "DocumentName" => document_name}
      |> maybe_put("Parameters", opts[:parameters])
      |> maybe_put("Comment", opts[:comment])
      |> maybe_put("TimeoutSeconds", opts[:timeout_seconds])
      |> maybe_put("DocumentVersion", opts[:document_version])
      |> maybe_put("DocumentHash", opts[:document_hash])
      |> maybe_put("DocumentHashType", opts[:document_hash_type])
      |> maybe_put("OutputS3BucketName", opts[:output_s3_bucket_name])
      |> maybe_put("OutputS3KeyPrefix", opts[:output_s3_key_prefix])
      |> maybe_put("CloudWatchOutputConfig", opts[:cloud_watch_output_config])
      |> maybe_put("MaxConcurrency", opts[:max_concurrency])
      |> maybe_put("MaxErrors", opts[:max_errors])
      |> maybe_put("ServiceRoleArn", opts[:service_role_arn])
      |> maybe_put("NotificationConfig", opts[:notification_config])

    with {:ok, op} <- build_operation("SendCommand", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Runs a command on nodes selected by targets (tag or resource-group
  criteria) instead of explicit instance IDs.

  AWS `SendCommand` accepts exactly one of `InstanceIds` or `Targets`;
  this is the `Targets` form of `send_command/3`.

  ## Arguments

    * `targets` - List of `%{key:, values:}` maps, e.g.
      `[%{key: "tag:Role", values: ["web"]}]` — encoded to the wire's
      `Key`/`Values`, like EC2's `%{name:, values:}` filters.
    * `document_name` - The SSM document to run.
    * `opts` - Same options as `send_command/3`.

  ## Examples

      AwsSDK.SSM.send_command_by_targets(
        [%{key: "tag:Role", values: ["web"]}],
        "AWS-RunShellScript",
        parameters: %{"commands" => ["uptime"]}
      )
      #=> {:ok, %{command: %{command_id: "0831e1a8-...", status: "Pending"}}}
  """
  @spec send_command_by_targets(
          targets :: [map()],
          document_name :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, %{command: map()}} | {:error, term()}
  def send_command_by_targets([_ | _] = targets, document_name, opts \\ [])
      when is_binary(document_name) do
    if sandbox?(opts) do
      sandbox_send_command_by_targets_response(targets, document_name, opts)
    else
      do_send_command_by_targets(targets, document_name, opts)
    end
  end

  defp do_send_command_by_targets(targets, document_name, opts) do
    wire_targets =
      Enum.map(targets, fn %{key: key, values: values} -> %{"Key" => key, "Values" => values} end)

    data =
      %{"Targets" => wire_targets, "DocumentName" => document_name}
      |> maybe_put("Parameters", opts[:parameters])
      |> maybe_put("Comment", opts[:comment])
      |> maybe_put("TimeoutSeconds", opts[:timeout_seconds])
      |> maybe_put("DocumentVersion", opts[:document_version])
      |> maybe_put("DocumentHash", opts[:document_hash])
      |> maybe_put("DocumentHashType", opts[:document_hash_type])
      |> maybe_put("OutputS3BucketName", opts[:output_s3_bucket_name])
      |> maybe_put("OutputS3KeyPrefix", opts[:output_s3_key_prefix])
      |> maybe_put("CloudWatchOutputConfig", opts[:cloud_watch_output_config])
      |> maybe_put("MaxConcurrency", opts[:max_concurrency])
      |> maybe_put("MaxErrors", opts[:max_errors])
      |> maybe_put("ServiceRoleArn", opts[:service_role_arn])
      |> maybe_put("NotificationConfig", opts[:notification_config])

    with {:ok, op} <- build_operation("SendCommand", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Returns detailed information about a command a specific node ran.

  deployd's polling loop: call until `:status` leaves `"Pending"`/
  `"InProgress"`/`"Delayed"`; treat `"Success"` as pass and `"Failed"`,
  `"Cancelled"`, or `"TimedOut"` as failure.

  ## Arguments

    * `command_id` - The parent command's ID (from `send_command/3`).
    * `instance_id` - The managed node the command ran on.
    * `opts` - Options:
      * `:plugin_name` - Name of the step/plugin for multi-plugin documents.

  ## Examples

      AwsSDK.SSM.get_command_invocation("0831e1a8-4c47-4c74-8f2a-EXAMPLE", "i-1234567890abcdef0")
      #=> {:ok,
      #=>  %{
      #=>    command_id: "0831e1a8-4c47-4c74-8f2a-EXAMPLE",
      #=>    instance_id: "i-1234567890abcdef0",
      #=>    document_name: "AWS-RunShellScript",
      #=>    document_version: "$DEFAULT",
      #=>    plugin_name: "aws:runShellScript",
      #=>    response_code: 0,
      #=>    execution_start_date_time: "2026-08-05T12:00:00.000Z",
      #=>    execution_elapsed_time: "PT0.5S",
      #=>    execution_end_date_time: "2026-08-05T12:00:01.000Z",
      #=>    status: "Success",
      #=>    status_details: "Success",
      #=>    standard_output_content: "ok\\n",
      #=>    standard_output_url: "",
      #=>    standard_error_content: "",
      #=>    standard_error_url: "",
      #=>    cloud_watch_output_config: %{
      #=>      cloud_watch_log_group_name: "",
      #=>      cloud_watch_output_enabled: false
      #=>    },
      #=>    comment: ""
      #=>  }}
  """
  @spec get_command_invocation(
          command_id :: String.t(),
          instance_id :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def get_command_invocation(command_id, instance_id, opts \\ [])
      when is_binary(command_id) and is_binary(instance_id) do
    if sandbox?(opts) do
      sandbox_get_command_invocation_response(command_id, instance_id, opts)
    else
      do_get_command_invocation(command_id, instance_id, opts)
    end
  end

  defp do_get_command_invocation(command_id, instance_id, opts) do
    data =
      %{"CommandId" => command_id, "InstanceId" => instance_id}
      |> maybe_put("PluginName", opts[:plugin_name])

    with {:ok, op} <- build_operation("GetCommandInvocation", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists the invocations of a command across nodes — the fleet-wide view of
  one `send_command/3` call.

  ## Options

    * `:command_id` - Restrict to one command's invocations.
    * `:instance_id` - Restrict to one node.
    * `:details` - Boolean; include per-plugin `command_plugins` detail.
    * `:filters` - List of `%{"key" => k, "value" => v}` maps
      (keys: `"InvokedAfter"`, `"InvokedBefore"`, `"Status"`, `"DocumentName"`).
    * `:max_results` - Integer page size (1-50).
    * `:next_token` - Pagination token.

  ## Examples

      AwsSDK.SSM.list_command_invocations(command_id: "0831e1a8-4c47-4c74-8f2a-EXAMPLE")
      #=> {:ok,
      #=>  %{
      #=>    command_invocations: [
      #=>      %{
      #=>        command_id: "0831e1a8-4c47-4c74-8f2a-EXAMPLE",
      #=>        instance_id: "i-1234567890abcdef0",
      #=>        instance_name: "",
      #=>        document_name: "AWS-RunShellScript",
      #=>        document_version: "$DEFAULT",
      #=>        requested_date_time: 1.7e9,
      #=>        status: "Success",
      #=>        status_details: "Success",
      #=>        command_plugins: [],
      #=>        service_role: "",
      #=>        notification_config: %{notification_arn: "", notification_events: [], notification_type: ""},
      #=>        cloud_watch_output_config: %{cloud_watch_log_group_name: "", cloud_watch_output_enabled: false}
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec list_command_invocations(opts :: keyword()) ::
          {:ok, %{command_invocations: [map()], next_token: String.t() | nil}} | {:error, term()}
  def list_command_invocations(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_command_invocations_response(opts)
    else
      do_list_command_invocations(opts)
    end
  end

  defp do_list_command_invocations(opts) do
    data =
      %{}
      |> maybe_put("CommandId", opts[:command_id])
      |> maybe_put("InstanceId", opts[:instance_id])
      |> maybe_put("Details", opts[:details])
      |> maybe_put("Filters", opts[:filters])
      |> maybe_put("MaxResults", opts[:max_results])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <- build_operation("ListCommandInvocations", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @doc false
  def build_operation(action, data, opts) do
    with {:ok, config} <-
           Client.resolve_config(:ssm, opts, &"ssm.#{&1}.amazonaws.com") do
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

      {:ok, apply_overrides(op, opts[:ssm] || [])}
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
    defdelegate sandbox_disabled?, to: AwsSDK.SSM.Sandbox

    @doc false
    defdelegate sandbox_get_parameter_response(name, opts),
      to: AwsSDK.SSM.Sandbox,
      as: :get_parameter_response

    @doc false
    defdelegate sandbox_get_parameters_response(names, opts),
      to: AwsSDK.SSM.Sandbox,
      as: :get_parameters_response

    @doc false
    defdelegate sandbox_get_parameters_by_path_response(path, opts),
      to: AwsSDK.SSM.Sandbox,
      as: :get_parameters_by_path_response

    @doc false
    defdelegate sandbox_put_parameter_response(name, value, opts),
      to: AwsSDK.SSM.Sandbox,
      as: :put_parameter_response

    @doc false
    defdelegate sandbox_delete_parameter_response(name, opts),
      to: AwsSDK.SSM.Sandbox,
      as: :delete_parameter_response

    @doc false
    defdelegate sandbox_delete_parameters_response(names, opts),
      to: AwsSDK.SSM.Sandbox,
      as: :delete_parameters_response

    @doc false
    defdelegate sandbox_describe_parameters_response(opts),
      to: AwsSDK.SSM.Sandbox,
      as: :describe_parameters_response

    @doc false
    defdelegate sandbox_describe_instance_information_response(opts),
      to: AwsSDK.SSM.Sandbox,
      as: :describe_instance_information_response

    @doc false
    defdelegate sandbox_send_command_response(instance_ids, document_name, opts),
      to: AwsSDK.SSM.Sandbox,
      as: :send_command_response

    @doc false
    defdelegate sandbox_send_command_by_targets_response(targets, document_name, opts),
      to: AwsSDK.SSM.Sandbox,
      as: :send_command_by_targets_response

    @doc false
    defdelegate sandbox_get_command_invocation_response(command_id, instance_id, opts),
      to: AwsSDK.SSM.Sandbox,
      as: :get_command_invocation_response

    @doc false
    defdelegate sandbox_list_command_invocations_response(opts),
      to: AwsSDK.SSM.Sandbox,
      as: :list_command_invocations_response
  else
    defp sandbox_disabled?, do: true

    defp sandbox_get_parameter_response(_, _), do: raise("sandbox not available")
    defp sandbox_get_parameters_response(_, _), do: raise("sandbox not available")
    defp sandbox_get_parameters_by_path_response(_, _), do: raise("sandbox not available")
    defp sandbox_put_parameter_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_delete_parameter_response(_, _), do: raise("sandbox not available")
    defp sandbox_delete_parameters_response(_, _), do: raise("sandbox not available")
    defp sandbox_describe_parameters_response(_), do: raise("sandbox not available")
    defp sandbox_describe_instance_information_response(_), do: raise("sandbox not available")
    defp sandbox_send_command_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_send_command_by_targets_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_get_command_invocation_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_list_command_invocations_response(_), do: raise("sandbox not available")
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
