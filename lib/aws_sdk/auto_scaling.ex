defmodule AwsSDK.AutoScaling do
  @moduledoc """
  `AwsSDK.AutoScaling` provides an API for AWS EC2 Auto Scaling.

  This module calls the AWS Auto Scaling Query API directly via `AwsSDK.HTTP`
  and `AwsSDK.Signer` (through `AwsSDK.Client`).

  Auto Scaling's public API is XML-only at the AWS wire level. The service
  model (`botocore/data/autoscaling/2011-01-01/service-2.json`) declares
  `metadata.protocols = ["query"]`, and AWS does not expose a JSON Auto
  Scaling endpoint. The form-urlencoded request / XML response handling
  here (XPath extraction via `SweetXml`) is a consequence of AWS's
  protocol choice, not a library decision.

  Auto Scaling is a regional service; requests are routed to
  `autoscaling.{region}.amazonaws.com`.

  ## Shared Options

  Credentials and region are flat top-level opts on every call (ex_aws shape).
  Each accepts a literal, a source tuple, or a list of sources (first
  non-nil wins):

    - `:access_key_id`, `:secret_access_key`, `:security_token`, `:region` -
      Sources: literal binary, `{:system, "ENV"}`, `:instance_role`,
      `:ecs_task_role`, `{:awscli, profile}` / `{:awscli, profile, ttl}`,
      a module, or a list of any of these.

  The following options are also available:

    - `:auto_scaling` - A keyword list of Auto Scaling endpoint overrides.
      Supported keys: `:scheme`, `:host`, `:port`. Credentials are not
      read from this sub-list; use the top-level keys above.

    - `:sandbox` - A keyword list to override sandbox configuration
      (`:enabled`).

  ## Sandbox

  Set `sandbox: [enabled: true]` to activate sandbox mode.

  Add the following to your `test_helper.exs`:

      AwsSDK.AutoScaling.Sandbox.start_link()

  Then register per-test response functions, e.g.:

      AwsSDK.AutoScaling.Sandbox.set_describe_auto_scaling_groups_responses([
        {"*", fn -> {:ok, %{auto_scaling_groups: [], next_token: nil}} end}
      ])
  """

  import SweetXml, only: [xpath: 2, xpath: 3, sigil_x: 2]

  alias AwsSDK.Operation

  alias AwsSDK.Client

  @service "autoscaling"
  @content_type "application/x-www-form-urlencoded"
  @api_version "2011-01-01"
  @default_region "us-east-1"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Describes Auto Scaling groups.

  Maps to AWS `DescribeAutoScalingGroups`.

  ## Options

    - `:auto_scaling_group_names` - list of ASG names
    - `:filters` - list of `%{name: ..., values: [...]}` maps
    - `:max_records` - integer
    - `:next_token` - pagination token
    - `:include_instances` - boolean

  See `AwsSDK.AutoScaling` shared options for credentials / region / endpoint.

  ## Examples

      AwsSDK.AutoScaling.describe_auto_scaling_groups(names: ["web-asg"])
      #=> {:ok,
      #=>  %{
      #=>    auto_scaling_groups: [
      #=>      %{
      #=>        auto_scaling_group_name: "web-asg",
      #=>        auto_scaling_group_arn: "arn:aws:autoscaling:us-east-1:123456789012:autoScalingGroup:uuid:autoScalingGroupName/web-asg",
      #=>        min_size: 1,
      #=>        max_size: 6,
      #=>        desired_capacity: 3,
      #=>        default_cooldown: 300,
      #=>        health_check_type: "ELB",
      #=>        health_check_grace_period: 300,
      #=>        created_time: "2026-01-01T00:00:00.000Z",
      #=>        new_instances_protected_from_scale_in: false,
      #=>        availability_zones: ["us-east-1a", "us-east-1b"],
      #=>        target_group_arns: ["arn:aws:elasticloadbalancing:...:targetgroup/web/abc"],
      #=>        launch_template: %{
      #=>          launch_template_id: "lt-0a1b2c3d4e5f6789a",
      #=>          launch_template_name: "web",
      #=>          version: "$Latest"
      #=>        },
      #=>        mixed_instances_policy: %{
      #=>          instances_distribution: %{
      #=>            on_demand_base_capacity: 1,
      #=>            on_demand_percentage_above_base_capacity: 0,
      #=>            spot_allocation_strategy: "capacity-optimized",
      #=>            spot_max_price: ""
      #=>          },
      #=>          launch_template: %{
      #=>            launch_template_specification: %{
      #=>              launch_template_id: "lt-0a1b2c3d4e5f6789a",
      #=>              launch_template_name: "web",
      #=>              version: "$Latest"
      #=>            },
      #=>            overrides: [
      #=>              %{instance_type: "t3.small", weighted_capacity: "2"}
      #=>            ]
      #=>          }
      #=>        },
      #=>        instances: [
      #=>          %{
      #=>            instance_id: "i-1234567890abcdef0",
      #=>            instance_type: "t3.small",
      #=>            availability_zone: "us-east-1a",
      #=>            lifecycle_state: "InService",
      #=>            health_status: "Healthy",
      #=>            protected_from_scale_in: false,
      #=>            launch_template: %{
      #=>              launch_template_id: "lt-0a1b2c3d4e5f6789a",
      #=>              version: "3"
      #=>            }
      #=>          }
      #=>        ],
      #=>        tags: [
      #=>          %{key: "Name", value: "web", propagate_at_launch: "true"}
      #=>        ]
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}

  `:mixed_instances_policy` keeps AWS's two levels: `:instances_distribution`
  and `:launch_template` (which itself holds a
  `:launch_template_specification` and `:overrides`).
  """
  @spec describe_auto_scaling_groups(keyword) :: {:ok, map} | {:error, term}
  def describe_auto_scaling_groups(opts \\ []) do
    if sandbox?(opts) do
      sandbox_describe_auto_scaling_groups_response(opts)
    else
      do_describe_auto_scaling_groups(opts)
    end
  end

  defp do_describe_auto_scaling_groups(opts) do
    params =
      flatten_query(%{
        "AutoScalingGroupNames" => opts[:auto_scaling_group_names],
        "Filters" => opts[:filters],
        "MaxRecords" => opts[:max_records],
        "NextToken" => opts[:next_token],
        "IncludeInstances" => opts[:include_instances]
      })

    with {:ok, op} <- build_operation("DescribeAutoScalingGroups", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, parse_describe_auto_scaling_groups(body)}
    end
  end

  @doc """
  Describes Auto Scaling instances.

  Maps to AWS `DescribeAutoScalingInstances`.

  ## Options

    - `:instance_ids` - list of instance IDs
    - `:max_records` - integer
    - `:next_token` - pagination token

  ## Examples

      AwsSDK.AutoScaling.describe_auto_scaling_instances(instance_ids: ["i-1234567890abcdef0"])
      #=> {:ok,
      #=>  %{
      #=>    auto_scaling_instances: [
      #=>      %{
      #=>        instance_id: "i-1234567890abcdef0",
      #=>        auto_scaling_group_name: "web-asg",
      #=>        availability_zone: "us-east-1a",
      #=>        lifecycle_state: "InService",
      #=>        health_status: "HEALTHY",
      #=>        instance_type: "t3.small",
      #=>        protected_from_scale_in: false,
      #=>        launch_template: %{
      #=>          launch_template_id: "lt-0a1b2c3d4e5f6789a",
      #=>          launch_template_name: "web",
      #=>          version: "3"
      #=>        }
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec describe_auto_scaling_instances(keyword) :: {:ok, map} | {:error, term}
  def describe_auto_scaling_instances(opts \\ []) do
    if sandbox?(opts) do
      sandbox_describe_auto_scaling_instances_response(opts)
    else
      do_describe_auto_scaling_instances(opts)
    end
  end

  defp do_describe_auto_scaling_instances(opts) do
    params =
      flatten_query(%{
        "InstanceIds" => opts[:instance_ids],
        "MaxRecords" => opts[:max_records],
        "NextToken" => opts[:next_token]
      })

    with {:ok, op} <- build_operation("DescribeAutoScalingInstances", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, parse_describe_auto_scaling_instances(body)}
    end
  end

  @doc """
  Describes instance refreshes for an Auto Scaling group.

  Maps to AWS `DescribeInstanceRefreshes`. `auto_scaling_group_name` is required.

  ## Options

    - `:instance_refresh_ids` - list of refresh IDs
    - `:max_records` - integer
    - `:next_token` - pagination token

  ## Examples

      AwsSDK.AutoScaling.describe_instance_refreshes("web-asg")
      #=> {:ok,
      #=>  %{
      #=>    instance_refreshes: [
      #=>      %{
      #=>        instance_refresh_id: "08b91cf7-8ec8-4d1b-9f0b-EXAMPLE",
      #=>        auto_scaling_group_name: "web-asg",
      #=>        status: "InProgress",
      #=>        status_reason: "Waiting for instances to warm up",
      #=>        start_time: "2026-01-01T00:00:00Z",
      #=>        end_time: "",
      #=>        percentage_complete: 33,
      #=>        instances_to_update: 2,
      #=>        strategy: "Rolling",
      #=>        preferences: %{
      #=>          min_healthy_percentage: 90,
      #=>          instance_warmup: 300,
      #=>          skip_matching: "false",
      #=>          checkpoint_percentages: [],
      #=>          alarm_specification: nil
      #=>        },
      #=>        progress_details: %{
      #=>          live_pool_progress: %{instances_to_update: 2, percentage_complete: 33},
      #=>          warm_pool_progress: nil
      #=>        },
      #=>        rollback_details: nil,
      #=>        desired_configuration: %{
      #=>          launch_template: %{
      #=>            launch_template_id: "lt-0a1b2c3d4e5f6789a",
      #=>            version: "4"
      #=>          },
      #=>          mixed_instances_policy: nil
      #=>        }
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec describe_instance_refreshes(String.t(), keyword) :: {:ok, map} | {:error, term}
  def describe_instance_refreshes(auto_scaling_group_name, opts \\ [])
      when is_binary(auto_scaling_group_name) do
    if sandbox?(opts) do
      sandbox_describe_instance_refreshes_response(auto_scaling_group_name, opts)
    else
      do_describe_instance_refreshes(auto_scaling_group_name, opts)
    end
  end

  defp do_describe_instance_refreshes(auto_scaling_group_name, opts) do
    params =
      flatten_query(%{
        "AutoScalingGroupName" => auto_scaling_group_name,
        "InstanceRefreshIds" => opts[:instance_refresh_ids],
        "MaxRecords" => opts[:max_records],
        "NextToken" => opts[:next_token]
      })

    with {:ok, op} <- build_operation("DescribeInstanceRefreshes", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, parse_describe_instance_refreshes(body)}
    end
  end

  @doc """
  Describes the scaling activities for an Auto Scaling group.

  Maps to AWS `DescribeScalingActivities`. `auto_scaling_group_name` is
  required here (AWS allows omitting it to list account-wide activity;
  this wrapper scopes to one group).

  ## Options

    - `:activity_ids` - list of activity IDs to fetch
    - `:include_deleted_groups` - boolean; include activity from deleted groups
    - `:max_records` - page size (max 100)
    - `:next_token` - pagination token

  ## Examples

      AwsSDK.AutoScaling.describe_scaling_activities("web-asg", max_records: 10)
      #=> {:ok,
      #=>  %{
      #=>    activities: [
      #=>      %{
      #=>        activity_id: "act-0abc",
      #=>        auto_scaling_group_name: "web-asg",
      #=>        description: "Terminating EC2 instance: i-0abc",
      #=>        cause: "At 2026-08-05T12:00:00Z an instance refresh replaced instances",
      #=>        start_time: "2026-08-05T12:00:00Z",
      #=>        end_time: "2026-08-05T12:05:00Z",
      #=>        status_code: "Successful",
      #=>        status_message: "",
      #=>        progress: 100,
      #=>        details: "{...}",
      #=>        auto_scaling_group_state: "",
      #=>        auto_scaling_group_arn: "arn:aws:autoscaling:..."
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec describe_scaling_activities(String.t(), keyword) :: {:ok, map} | {:error, term}
  def describe_scaling_activities(auto_scaling_group_name, opts \\ [])
      when is_binary(auto_scaling_group_name) do
    if sandbox?(opts) do
      sandbox_describe_scaling_activities_response(auto_scaling_group_name, opts)
    else
      do_describe_scaling_activities(auto_scaling_group_name, opts)
    end
  end

  defp do_describe_scaling_activities(auto_scaling_group_name, opts) do
    params =
      flatten_query(%{
        "AutoScalingGroupName" => auto_scaling_group_name,
        "ActivityIds" => opts[:activity_ids],
        "IncludeDeletedGroups" => opts[:include_deleted_groups],
        "MaxRecords" => opts[:max_records],
        "NextToken" => opts[:next_token]
      })

    with {:ok, op} <- build_operation("DescribeScalingActivities", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, parse_describe_scaling_activities(body)}
    end
  end

  @doc """
  Starts an instance refresh for an Auto Scaling group.

  Maps to AWS `StartInstanceRefresh`. `auto_scaling_group_name` is required.

  ## Options

    - `:strategy` - refresh strategy (e.g. `"Rolling"`)
    - `:preferences` - map passed verbatim to AWS `Preferences` (any field
      AWS accepts; flattened by the generic Query encoder)
    - `:desired_configuration` - map passed verbatim to AWS
      `DesiredConfiguration`

  ## Examples

      AwsSDK.AutoScaling.start_instance_refresh("web-asg",
        preferences: %{min_healthy_percentage: 90, instance_warmup: 300}
      )
      #=> {:ok, %{instance_refresh_id: "08b91cf7-8ec8-4d1b-9f0b-EXAMPLE"}}
  """
  @spec start_instance_refresh(String.t(), keyword) :: {:ok, map} | {:error, term}
  def start_instance_refresh(auto_scaling_group_name, opts \\ [])
      when is_binary(auto_scaling_group_name) do
    if sandbox?(opts) do
      sandbox_start_instance_refresh_response(auto_scaling_group_name, opts)
    else
      do_start_instance_refresh(auto_scaling_group_name, opts)
    end
  end

  defp do_start_instance_refresh(auto_scaling_group_name, opts) do
    params =
      flatten_query(%{
        "AutoScalingGroupName" => auto_scaling_group_name,
        "Strategy" => opts[:strategy],
        "Preferences" => opts[:preferences],
        "DesiredConfiguration" => opts[:desired_configuration]
      })

    with {:ok, op} <- build_operation("StartInstanceRefresh", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, parse_start_instance_refresh(body)}
    end
  end

  @doc """
  Cancels an in-progress instance refresh.

  Maps to AWS `CancelInstanceRefresh`. `auto_scaling_group_name` is required.

  ## Examples

      AwsSDK.AutoScaling.cancel_instance_refresh("web-asg")
      #=> {:ok, %{instance_refresh_id: "08b91cf7-8ec8-4d1b-9f0b-EXAMPLE"}}
  """
  @spec cancel_instance_refresh(String.t(), keyword) :: {:ok, map} | {:error, term}
  def cancel_instance_refresh(auto_scaling_group_name, opts \\ [])
      when is_binary(auto_scaling_group_name) do
    if sandbox?(opts) do
      sandbox_cancel_instance_refresh_response(auto_scaling_group_name, opts)
    else
      do_cancel_instance_refresh(auto_scaling_group_name, opts)
    end
  end

  defp do_cancel_instance_refresh(auto_scaling_group_name, opts) do
    params = flatten_query(%{"AutoScalingGroupName" => auto_scaling_group_name})

    with {:ok, op} <- build_operation("CancelInstanceRefresh", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, parse_cancel_instance_refresh(body)}
    end
  end

  @doc """
  Rolls back an in-progress or recent instance refresh.

  Maps to AWS `RollbackInstanceRefresh`. `auto_scaling_group_name` is required.

  ## Examples

      AwsSDK.AutoScaling.rollback_instance_refresh("web-asg")
      #=> {:ok, %{instance_refresh_id: "08b91cf7-8ec8-4d1b-9f0b-EXAMPLE"}}
  """
  @spec rollback_instance_refresh(String.t(), keyword) :: {:ok, map} | {:error, term}
  def rollback_instance_refresh(auto_scaling_group_name, opts \\ [])
      when is_binary(auto_scaling_group_name) do
    if sandbox?(opts) do
      sandbox_rollback_instance_refresh_response(auto_scaling_group_name, opts)
    else
      do_rollback_instance_refresh(auto_scaling_group_name, opts)
    end
  end

  defp do_rollback_instance_refresh(auto_scaling_group_name, opts) do
    params = flatten_query(%{"AutoScalingGroupName" => auto_scaling_group_name})

    with {:ok, op} <- build_operation("RollbackInstanceRefresh", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, parse_rollback_instance_refresh(body)}
    end
  end

  @doc """
  Completes a pending lifecycle action.

  Maps to AWS `CompleteLifecycleAction`.

  ## Arguments

    - `lifecycle_hook_name`
    - `auto_scaling_group_name`
    - `lifecycle_action_result` - `"CONTINUE"` or `"ABANDON"`
    - `opts` - options below, plus shared credentials / region / endpoint

  ## Options

    - `:lifecycle_action_token`
    - `:instance_id`

  ## Examples

      AwsSDK.AutoScaling.complete_lifecycle_action(
        "web-asg-launch-hook",
        "web-asg",
        "CONTINUE",
        instance_id: "i-1234567890abcdef0"
      )
      #=> {:ok, %{}}

  AWS returns an empty result for this operation.
  """
  @spec complete_lifecycle_action(
          lifecycle_hook_name :: String.t(),
          auto_scaling_group_name :: String.t(),
          lifecycle_action_result :: String.t(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def complete_lifecycle_action(
        lifecycle_hook_name,
        auto_scaling_group_name,
        lifecycle_action_result,
        opts \\ []
      )
      when is_binary(lifecycle_hook_name) and is_binary(auto_scaling_group_name) and
             is_binary(lifecycle_action_result) do
    if sandbox?(opts) do
      sandbox_complete_lifecycle_action_response(
        lifecycle_hook_name,
        auto_scaling_group_name,
        lifecycle_action_result,
        opts
      )
    else
      do_complete_lifecycle_action(
        lifecycle_hook_name,
        auto_scaling_group_name,
        lifecycle_action_result,
        opts
      )
    end
  end

  defp do_complete_lifecycle_action(
         lifecycle_hook_name,
         auto_scaling_group_name,
         lifecycle_action_result,
         opts
       ) do
    params =
      flatten_query(%{
        "LifecycleHookName" => lifecycle_hook_name,
        "AutoScalingGroupName" => auto_scaling_group_name,
        "LifecycleActionResult" => lifecycle_action_result,
        "LifecycleActionToken" => opts[:lifecycle_action_token],
        "InstanceId" => opts[:instance_id]
      })

    with {:ok, op} <- build_operation("CompleteLifecycleAction", params, opts),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Records a heartbeat for a pending lifecycle action.

  Maps to AWS `RecordLifecycleActionHeartbeat`.

  ## Arguments

    - `lifecycle_hook_name`
    - `auto_scaling_group_name`
    - `opts` - options below, plus shared credentials / region / endpoint

  ## Options

    - `:lifecycle_action_token`
    - `:instance_id`

  ## Examples

      AwsSDK.AutoScaling.record_lifecycle_action_heartbeat(
        "web-asg-launch-hook",
        "web-asg",
        instance_id: "i-1234567890abcdef0"
      )
      #=> {:ok, %{}}
  """
  @spec record_lifecycle_action_heartbeat(
          lifecycle_hook_name :: String.t(),
          auto_scaling_group_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def record_lifecycle_action_heartbeat(lifecycle_hook_name, auto_scaling_group_name, opts \\ [])
      when is_binary(lifecycle_hook_name) and is_binary(auto_scaling_group_name) do
    if sandbox?(opts) do
      sandbox_record_lifecycle_action_heartbeat_response(
        lifecycle_hook_name,
        auto_scaling_group_name,
        opts
      )
    else
      do_record_lifecycle_action_heartbeat(lifecycle_hook_name, auto_scaling_group_name, opts)
    end
  end

  defp do_record_lifecycle_action_heartbeat(
         lifecycle_hook_name,
         auto_scaling_group_name,
         opts
       ) do
    params =
      flatten_query(%{
        "LifecycleHookName" => lifecycle_hook_name,
        "AutoScalingGroupName" => auto_scaling_group_name,
        "LifecycleActionToken" => opts[:lifecycle_action_token],
        "InstanceId" => opts[:instance_id]
      })

    with {:ok, op} <- build_operation("RecordLifecycleActionHeartbeat", params, opts),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Sets the health status for an instance.

  Maps to AWS `SetInstanceHealth`.

  ## Options

    - `:should_respect_grace_period` - boolean

  ## Examples

      AwsSDK.AutoScaling.set_instance_health("i-1234567890abcdef0", "Unhealthy")
      #=> {:ok, %{}}

      # Keep the group's grace period from masking the change.
      AwsSDK.AutoScaling.set_instance_health("i-1234567890abcdef0", "Unhealthy",
        should_respect_grace_period: false
      )
      #=> {:ok, %{}}
  """
  @spec set_instance_health(String.t(), String.t(), keyword) :: {:ok, map} | {:error, term}
  def set_instance_health(instance_id, health_status, opts \\ [])
      when is_binary(instance_id) and is_binary(health_status) do
    if sandbox?(opts) do
      sandbox_set_instance_health_response(instance_id, health_status, opts)
    else
      do_set_instance_health(instance_id, health_status, opts)
    end
  end

  defp do_set_instance_health(instance_id, health_status, opts) do
    params =
      flatten_query(%{
        "InstanceId" => instance_id,
        "HealthStatus" => health_status,
        "ShouldRespectGracePeriod" => opts[:should_respect_grace_period]
      })

    with {:ok, op} <- build_operation("SetInstanceHealth", params, opts),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Terminates an instance within an Auto Scaling group.

  Maps to AWS `TerminateInstanceInAutoScalingGroup`.
  `should_decrement_desired_capacity` is required and must be a boolean.

  Returns the resulting `Activity` from AWS as a map under `:activity`.

  ## Examples

      AwsSDK.AutoScaling.terminate_instance_in_auto_scaling_group(
        "i-1234567890abcdef0",
        true
      )
      #=> {:ok,
      #=>  %{
      #=>    activity: %{
      #=>      activity_id: "e54ff599-bf05-4076-8b95-EXAMPLE",
      #=>      auto_scaling_group_name: "web-asg",
      #=>      cause: "At 2026-01-01T00:00:00Z an instance was taken out of service in response to a user request, shrinking the capacity from 3 to 2.",
      #=>      description: "Terminating EC2 instance: i-1234567890abcdef0",
      #=>      details: "{\"Subnet ID\":\"subnet-9d4a7b6c\",\"Availability Zone\":\"us-east-1a\"}",
      #=>      status_code: "InProgress",
      #=>      start_time: "2026-01-01T00:00:00.000Z",
      #=>      end_time: "",
      #=>      progress: 0
      #=>    }
      #=>  }}

  The second argument decides whether the group's desired capacity shrinks
  with the termination.
  """
  @spec terminate_instance_in_auto_scaling_group(String.t(), boolean, keyword) ::
          {:ok, map} | {:error, term}
  def terminate_instance_in_auto_scaling_group(
        instance_id,
        should_decrement_desired_capacity,
        opts \\ []
      )
      when is_binary(instance_id) and is_boolean(should_decrement_desired_capacity) do
    if sandbox?(opts) do
      sandbox_terminate_instance_in_auto_scaling_group_response(
        instance_id,
        should_decrement_desired_capacity,
        opts
      )
    else
      do_terminate_instance_in_auto_scaling_group(
        instance_id,
        should_decrement_desired_capacity,
        opts
      )
    end
  end

  defp do_terminate_instance_in_auto_scaling_group(
         instance_id,
         should_decrement_desired_capacity,
         opts
       ) do
    params =
      flatten_query(%{
        "InstanceId" => instance_id,
        "ShouldDecrementDesiredCapacity" => should_decrement_desired_capacity
      })

    with {:ok, op} <- build_operation("TerminateInstanceInAutoScalingGroup", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, parse_terminate_instance_in_auto_scaling_group(body)}
    end
  end

  @doc """
  Sets the desired capacity for an Auto Scaling group.

  Maps to AWS `SetDesiredCapacity`.

  ## Options

    - `:honor_cooldown` - boolean

  ## Examples

      AwsSDK.AutoScaling.set_desired_capacity("web-asg", 5)
      #=> {:ok, %{}}

      # Let the group's cooldown gate the change.
      AwsSDK.AutoScaling.set_desired_capacity("web-asg", 5, honor_cooldown: true)
      #=> {:ok, %{}}
  """
  @spec set_desired_capacity(String.t(), integer, keyword) :: {:ok, map} | {:error, term}
  def set_desired_capacity(auto_scaling_group_name, desired_capacity, opts \\ [])
      when is_binary(auto_scaling_group_name) and is_integer(desired_capacity) do
    if sandbox?(opts) do
      sandbox_set_desired_capacity_response(auto_scaling_group_name, desired_capacity, opts)
    else
      do_set_desired_capacity(auto_scaling_group_name, desired_capacity, opts)
    end
  end

  defp do_set_desired_capacity(auto_scaling_group_name, desired_capacity, opts) do
    params =
      flatten_query(%{
        "AutoScalingGroupName" => auto_scaling_group_name,
        "DesiredCapacity" => desired_capacity,
        "HonorCooldown" => opts[:honor_cooldown]
      })

    with {:ok, op} <- build_operation("SetDesiredCapacity", params, opts),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  # ---------------------------------------------------------------------------
  # Request building
  # ---------------------------------------------------------------------------

  @doc false
  def build_operation(action, params, opts) do
    opts = Keyword.put_new(opts, :region, @default_region)

    with {:ok, config} <- Client.resolve_config(:auto_scaling, opts, &default_host/1) do
      op = %Operation{
        method: :post,
        url: Client.simple_url(config),
        headers: [{"content-type", @content_type}],
        body: encode_body(action, params),
        service: @service,
        region: config.region,
        access_key_id: config.access_key_id,
        secret_access_key: config.secret_access_key,
        security_token: config.security_token,
        http: Keyword.get(opts, :http, [])
      }

      {:ok, apply_overrides(op, opts[:auto_scaling] || [])}
    end
  end

  defp default_host(region), do: "autoscaling.#{region}.amazonaws.com"

  defp encode_body(action, params) do
    params
    |> Map.merge(%{"Action" => action, "Version" => @api_version})
    |> URI.encode_query()
  end

  @doc false
  defdelegate flatten_query(input), to: AwsSDK.Query, as: :encode

  # ---------------------------------------------------------------------------
  # Response error wrapping
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Sandbox delegation
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # XML parsers
  # ---------------------------------------------------------------------------

  @doc false
  def parse_describe_auto_scaling_groups_for_test(xml),
    do: parse_describe_auto_scaling_groups(xml)

  defp parse_describe_auto_scaling_groups(body) do
    result =
      xpath(body, ~x"//DescribeAutoScalingGroupsResult"e,
        groups: [
          ~x"./AutoScalingGroups/member"l,
          auto_scaling_group_name: ~x"./AutoScalingGroupName/text()"s,
          auto_scaling_group_arn: ~x"./AutoScalingGroupARN/text()"s,
          launch_configuration_name: ~x"./LaunchConfigurationName/text()"s,
          min_size: ~x"./MinSize/text()"i,
          max_size: ~x"./MaxSize/text()"i,
          desired_capacity: ~x"./DesiredCapacity/text()"i,
          default_cooldown: ~x"./DefaultCooldown/text()"i,
          availability_zones: ~x"./AvailabilityZones/member/text()"sl,
          load_balancer_names: ~x"./LoadBalancerNames/member/text()"sl,
          target_group_arns: ~x"./TargetGroupARNs/member/text()"sl,
          health_check_type: ~x"./HealthCheckType/text()"s,
          health_check_grace_period: ~x"./HealthCheckGracePeriod/text()"oi,
          created_time: ~x"./CreatedTime/text()"s,
          vpc_zone_identifier: ~x"./VPCZoneIdentifier/text()"s,
          service_linked_role_arn: ~x"./ServiceLinkedRoleARN/text()"s,
          new_instances_protected_from_scale_in: ~x"./NewInstancesProtectedFromScaleIn/text()"s,
          termination_policies: ~x"./TerminationPolicies/member/text()"sl,
          availability_zone_ids: ~x"./AvailabilityZoneIds/member/text()"sl,
          capacity_rebalance: ~x"./CapacityRebalance/text()"os,
          # Required: No -- must not use a plain integer cast.
          default_instance_warmup: ~x"./DefaultInstanceWarmup/text()"oi,
          max_instance_lifetime: ~x"./MaxInstanceLifetime/text()"oi,
          predicted_capacity: ~x"./PredictedCapacity/text()"oi,
          warm_pool_size: ~x"./WarmPoolSize/text()"oi,
          deletion_protection: ~x"./DeletionProtection/text()"os,
          desired_capacity_type: ~x"./DesiredCapacityType/text()"os,
          placement_group: ~x"./PlacementGroup/text()"os,
          status: ~x"./Status/text()"os,
          suspended_processes: [
            ~x"./SuspendedProcesses/member"l,
            process_name: ~x"./ProcessName/text()"os,
            suspension_reason: ~x"./SuspensionReason/text()"os
          ],
          enabled_metrics: [
            ~x"./EnabledMetrics/member"l,
            metric: ~x"./Metric/text()"os,
            granularity: ~x"./Granularity/text()"os
          ],
          tags: [
            ~x"./Tags/member"l,
            key: ~x"./Key/text()"os,
            value: ~x"./Value/text()"os,
            resource_id: ~x"./ResourceId/text()"os,
            resource_type: ~x"./ResourceType/text()"os,
            propagate_at_launch: ~x"./PropagateAtLaunch/text()"os
          ],
          traffic_sources: [
            ~x"./TrafficSources/member"l,
            identifier: ~x"./Identifier/text()"s,
            type: ~x"./Type/text()"os
          ],
          launch_template: [
            ~x"./LaunchTemplate"o,
            launch_template_id: ~x"./LaunchTemplateId/text()"os,
            launch_template_name: ~x"./LaunchTemplateName/text()"os,
            version: ~x"./Version/text()"os
          ],
          instance_maintenance_policy: [
            ~x"./InstanceMaintenancePolicy"o,
            # -1 is a real sentinel here, not an absent value.
            max_healthy_percentage: ~x"./MaxHealthyPercentage/text()"oi,
            min_healthy_percentage: ~x"./MinHealthyPercentage/text()"oi
          ],
          availability_zone_distribution: [
            ~x"./AvailabilityZoneDistribution"o,
            capacity_distribution_strategy: ~x"./CapacityDistributionStrategy/text()"os
          ],
          availability_zone_impairment_policy: [
            ~x"./AvailabilityZoneImpairmentPolicy"o,
            impaired_zone_health_check_behavior: ~x"./ImpairedZoneHealthCheckBehavior/text()"os,
            zonal_shift_enabled: ~x"./ZonalShiftEnabled/text()"os
          ],
          capacity_reservation_specification: [
            ~x"./CapacityReservationSpecification"o,
            capacity_reservation_preference: ~x"./CapacityReservationPreference/text()"os,
            capacity_reservation_target: [
              ~x"./CapacityReservationTarget"o,
              capacity_reservation_ids: ~x"./CapacityReservationIds/member/text()"sl,
              # `Arns` here is mixed case, unlike TargetGroupARNs above.
              capacity_reservation_resource_group_arns:
                ~x"./CapacityReservationResourceGroupArns/member/text()"sl
            ]
          ],
          warm_pool_configuration: [
            ~x"./WarmPoolConfiguration"o,
            max_group_prepared_capacity: ~x"./MaxGroupPreparedCapacity/text()"oi,
            min_size: ~x"./MinSize/text()"oi,
            pool_state: ~x"./PoolState/text()"os,
            status: ~x"./Status/text()"os,
            instance_reuse_policy: [
              ~x"./InstanceReusePolicy"o,
              reuse_on_scale_in: ~x"./ReuseOnScaleIn/text()"os
            ]
          ],
          mixed_instances_policy: [
            ~x"./MixedInstancesPolicy"o,
            instances_distribution: [
              ~x"./InstancesDistribution"o,
              on_demand_allocation_strategy: ~x"./OnDemandAllocationStrategy/text()"os,
              on_demand_base_capacity: ~x"./OnDemandBaseCapacity/text()"oi,
              on_demand_percentage_above_base_capacity:
                ~x"./OnDemandPercentageAboveBaseCapacity/text()"oi,
              spot_allocation_strategy: ~x"./SpotAllocationStrategy/text()"os,
              spot_instance_pools: ~x"./SpotInstancePools/text()"oi,
              # SpotMaxPrice is a String in the model despite looking numeric.
              spot_max_price: ~x"./SpotMaxPrice/text()"os
            ],
            launch_template: [
              ~x"./LaunchTemplate"o,
              launch_template_specification: [
                ~x"./LaunchTemplateSpecification"o,
                launch_template_id: ~x"./LaunchTemplateId/text()"os,
                launch_template_name: ~x"./LaunchTemplateName/text()"os,
                version: ~x"./Version/text()"os
              ],
              overrides: [
                ~x"./Overrides/member"l,
                instance_type: ~x"./InstanceType/text()"os,
                image_id: ~x"./ImageId/text()"os,
                # String in the model, not an integer.
                weighted_capacity: ~x"./WeightedCapacity/text()"os,
                launch_template_specification: [
                  ~x"./LaunchTemplateSpecification"o,
                  launch_template_id: ~x"./LaunchTemplateId/text()"os,
                  launch_template_name: ~x"./LaunchTemplateName/text()"os,
                  version: ~x"./Version/text()"os
                ]
              ]
            ]
          ],
          instances: [
            ~x"./Instances/member"l,
            instance_id: ~x"./InstanceId/text()"s,
            instance_type: ~x"./InstanceType/text()"s,
            availability_zone: ~x"./AvailabilityZone/text()"s,
            availability_zone_id: ~x"./AvailabilityZoneId/text()"os,
            image_id: ~x"./ImageId/text()"os,
            weighted_capacity: ~x"./WeightedCapacity/text()"os,
            lifecycle_state: ~x"./LifecycleState/text()"s,
            health_status: ~x"./HealthStatus/text()"s,
            launch_configuration_name: ~x"./LaunchConfigurationName/text()"s,
            protected_from_scale_in: ~x"./ProtectedFromScaleIn/text()"s,
            launch_template: [
              ~x"./LaunchTemplate"o,
              launch_template_id: ~x"./LaunchTemplateId/text()"os,
              launch_template_name: ~x"./LaunchTemplateName/text()"os,
              version: ~x"./Version/text()"os
            ]
          ]
        ],
        next_token: ~x"./NextToken/text()"s
      )

    groups =
      Enum.map(result.groups, fn g ->
        g
        |> Map.update!(:new_instances_protected_from_scale_in, &boolish/1)
        |> Map.update!(:instances, fn instances ->
          Enum.map(instances, fn i ->
            Map.update!(i, :protected_from_scale_in, &(&1 === "true"))
          end)
        end)
      end)

    %{auto_scaling_groups: groups, next_token: nilify(result.next_token)}
  end

  defp boolish("true"), do: true
  defp boolish("false"), do: false
  defp boolish(""), do: nil
  defp boolish(other), do: other

  defp parse_describe_auto_scaling_instances(body) do
    result =
      xpath(body, ~x"//DescribeAutoScalingInstancesResult"e,
        instances: [
          ~x"./AutoScalingInstances/member"l,
          instance_id: ~x"./InstanceId/text()"s,
          auto_scaling_group_name: ~x"./AutoScalingGroupName/text()"s,
          availability_zone: ~x"./AvailabilityZone/text()"s,
          lifecycle_state: ~x"./LifecycleState/text()"s,
          health_status: ~x"./HealthStatus/text()"s,
          launch_configuration_name: ~x"./LaunchConfigurationName/text()"s,
          instance_type: ~x"./InstanceType/text()"s,
          protected_from_scale_in: ~x"./ProtectedFromScaleIn/text()"s,
          availability_zone_id: ~x"./AvailabilityZoneId/text()"os,
          image_id: ~x"./ImageId/text()"os,
          # String in the model, not an integer.
          weighted_capacity: ~x"./WeightedCapacity/text()"os,
          launch_template: [
            ~x"./LaunchTemplate"o,
            launch_template_id: ~x"./LaunchTemplateId/text()"os,
            launch_template_name: ~x"./LaunchTemplateName/text()"os,
            version: ~x"./Version/text()"os
          ]
        ],
        next_token: ~x"./NextToken/text()"s
      )

    instances =
      Enum.map(result.instances, fn i ->
        Map.update!(i, :protected_from_scale_in, &(&1 === "true"))
      end)

    %{auto_scaling_instances: instances, next_token: nilify(result.next_token)}
  end

  @doc false
  def parse_describe_scaling_activities_for_test(xml), do: parse_describe_scaling_activities(xml)

  defp parse_describe_scaling_activities(body) do
    result =
      xpath(body, ~x"//DescribeScalingActivitiesResult"e,
        activities: [
          ~x"./Activities/member"l,
          activity_id: ~x"./ActivityId/text()"s,
          auto_scaling_group_name: ~x"./AutoScalingGroupName/text()"s,
          description: ~x"./Description/text()"os,
          cause: ~x"./Cause/text()"os,
          start_time: ~x"./StartTime/text()"os,
          end_time: ~x"./EndTime/text()"os,
          status_code: ~x"./StatusCode/text()"os,
          status_message: ~x"./StatusMessage/text()"os,
          progress: ~x"./Progress/text()"oi,
          details: ~x"./Details/text()"os,
          auto_scaling_group_state: ~x"./AutoScalingGroupState/text()"os,
          auto_scaling_group_arn: ~x"./AutoScalingGroupARN/text()"os
        ],
        next_token: ~x"./NextToken/text()"s
      )

    %{activities: result.activities, next_token: nilify(result.next_token)}
  end

  defp parse_describe_instance_refreshes(body) do
    result =
      xpath(body, ~x"//DescribeInstanceRefreshesResult"e,
        instance_refreshes: [
          ~x"./InstanceRefreshes/member"l,
          instance_refresh_id: ~x"./InstanceRefreshId/text()"s,
          auto_scaling_group_name: ~x"./AutoScalingGroupName/text()"s,
          status: ~x"./Status/text()"s,
          status_reason: ~x"./StatusReason/text()"s,
          start_time: ~x"./StartTime/text()"s,
          end_time: ~x"./EndTime/text()"s,
          percentage_complete: ~x"./PercentageComplete/text()"oi,
          instances_to_update: ~x"./InstancesToUpdate/text()"oi,
          # `Preferences` is a RefreshPreferences structure. Reading it as a
          # text node yielded "" for any refresh started with real preferences,
          # dropping the data silently.
          preferences: [
            ~x"./Preferences"o,
            auto_rollback: ~x"./AutoRollback/text()"os,
            min_healthy_percentage: ~x"./MinHealthyPercentage/text()"oi,
            max_healthy_percentage: ~x"./MaxHealthyPercentage/text()"oi,
            instance_warmup: ~x"./InstanceWarmup/text()"oi,
            checkpoint_delay: ~x"./CheckpointDelay/text()"oi,
            skip_matching: ~x"./SkipMatching/text()"os,
            scale_in_protected_instances: ~x"./ScaleInProtectedInstances/text()"os,
            standby_instances: ~x"./StandbyInstances/text()"os,
            bake_time: ~x"./BakeTime/text()"oi,
            checkpoint_percentages: ~x"./CheckpointPercentages/member/text()"sl,
            alarm_specification: [
              ~x"./AlarmSpecification"o,
              alarms: ~x"./Alarms/member/text()"sl
            ]
          ],
          strategy: ~x"./Strategy/text()"os,
          progress_details: [
            ~x"./ProgressDetails"o,
            live_pool_progress: [
              ~x"./LivePoolProgress"o,
              instances_to_update: ~x"./InstancesToUpdate/text()"oi,
              percentage_complete: ~x"./PercentageComplete/text()"oi
            ],
            warm_pool_progress: [
              ~x"./WarmPoolProgress"o,
              instances_to_update: ~x"./InstancesToUpdate/text()"oi,
              percentage_complete: ~x"./PercentageComplete/text()"oi
            ]
          ],
          rollback_details: [
            ~x"./RollbackDetails"o,
            instances_to_update_on_rollback: ~x"./InstancesToUpdateOnRollback/text()"oi,
            percentage_complete_on_rollback: ~x"./PercentageCompleteOnRollback/text()"oi,
            rollback_reason: ~x"./RollbackReason/text()"os,
            rollback_start_time: ~x"./RollbackStartTime/text()"os
          ],
          desired_configuration: [
            ~x"./DesiredConfiguration"o,
            launch_template: [
              ~x"./LaunchTemplate"o,
              launch_template_id: ~x"./LaunchTemplateId/text()"os,
              launch_template_name: ~x"./LaunchTemplateName/text()"os,
              version: ~x"./Version/text()"os
            ],
            mixed_instances_policy: [
              ~x"./MixedInstancesPolicy"o,
              instances_distribution: [
                ~x"./InstancesDistribution"o,
                on_demand_allocation_strategy: ~x"./OnDemandAllocationStrategy/text()"os,
                on_demand_base_capacity: ~x"./OnDemandBaseCapacity/text()"oi,
                on_demand_percentage_above_base_capacity:
                  ~x"./OnDemandPercentageAboveBaseCapacity/text()"oi,
                spot_allocation_strategy: ~x"./SpotAllocationStrategy/text()"os,
                spot_instance_pools: ~x"./SpotInstancePools/text()"oi,
                spot_max_price: ~x"./SpotMaxPrice/text()"os
              ],
              launch_template: [
                ~x"./LaunchTemplate"o,
                launch_template_specification: [
                  ~x"./LaunchTemplateSpecification"o,
                  launch_template_id: ~x"./LaunchTemplateId/text()"os,
                  launch_template_name: ~x"./LaunchTemplateName/text()"os,
                  version: ~x"./Version/text()"os
                ],
                overrides: [
                  ~x"./Overrides/member"l,
                  instance_type: ~x"./InstanceType/text()"os,
                  image_id: ~x"./ImageId/text()"os,
                  weighted_capacity: ~x"./WeightedCapacity/text()"os,
                  launch_template_specification: [
                    ~x"./LaunchTemplateSpecification"o,
                    launch_template_id: ~x"./LaunchTemplateId/text()"os,
                    launch_template_name: ~x"./LaunchTemplateName/text()"os,
                    version: ~x"./Version/text()"os
                  ]
                ]
              ]
            ]
          ]
        ],
        next_token: ~x"./NextToken/text()"s
      )

    %{
      instance_refreshes: result.instance_refreshes,
      next_token: nilify(result.next_token)
    }
  end

  defp parse_start_instance_refresh(body) do
    %{
      instance_refresh_id: xpath(body, ~x"//StartInstanceRefreshResult/InstanceRefreshId/text()"s)
    }
  end

  defp parse_cancel_instance_refresh(body) do
    %{
      instance_refresh_id:
        xpath(body, ~x"//CancelInstanceRefreshResult/InstanceRefreshId/text()"s)
    }
  end

  defp parse_rollback_instance_refresh(body) do
    %{
      instance_refresh_id:
        xpath(body, ~x"//RollbackInstanceRefreshResult/InstanceRefreshId/text()"s)
    }
  end

  defp parse_terminate_instance_in_auto_scaling_group(body) do
    activity =
      xpath(body, ~x"//TerminateInstanceInAutoScalingGroupResult/Activity"e,
        activity_id: ~x"./ActivityId/text()"s,
        auto_scaling_group_name: ~x"./AutoScalingGroupName/text()"s,
        cause: ~x"./Cause/text()"s,
        description: ~x"./Description/text()"s,
        details: ~x"./Details/text()"s,
        progress: ~x"./Progress/text()"oi,
        status_code: ~x"./StatusCode/text()"s,
        start_time: ~x"./StartTime/text()"s,
        end_time: ~x"./EndTime/text()"os,
        status_message: ~x"./StatusMessage/text()"os,
        auto_scaling_group_arn: ~x"./AutoScalingGroupARN/text()"os,
        auto_scaling_group_state: ~x"./AutoScalingGroupState/text()"os
      )

    %{activity: activity}
  end

  defp nilify(""), do: nil
  defp nilify(other), do: other

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
    defdelegate sandbox_disabled?, to: AwsSDK.AutoScaling.Sandbox

    @doc false
    defdelegate sandbox_describe_auto_scaling_groups_response(opts),
      to: AwsSDK.AutoScaling.Sandbox,
      as: :describe_auto_scaling_groups_response

    @doc false
    defdelegate sandbox_describe_auto_scaling_instances_response(opts),
      to: AwsSDK.AutoScaling.Sandbox,
      as: :describe_auto_scaling_instances_response

    @doc false
    defdelegate sandbox_describe_instance_refreshes_response(asg, opts),
      to: AwsSDK.AutoScaling.Sandbox,
      as: :describe_instance_refreshes_response

    @doc false
    defdelegate sandbox_describe_scaling_activities_response(asg, opts),
      to: AwsSDK.AutoScaling.Sandbox,
      as: :describe_scaling_activities_response

    @doc false
    defdelegate sandbox_start_instance_refresh_response(asg, opts),
      to: AwsSDK.AutoScaling.Sandbox,
      as: :start_instance_refresh_response

    @doc false
    defdelegate sandbox_cancel_instance_refresh_response(asg, opts),
      to: AwsSDK.AutoScaling.Sandbox,
      as: :cancel_instance_refresh_response

    @doc false
    defdelegate sandbox_rollback_instance_refresh_response(asg, opts),
      to: AwsSDK.AutoScaling.Sandbox,
      as: :rollback_instance_refresh_response

    @doc false
    defdelegate sandbox_complete_lifecycle_action_response(hook, asg, result, opts),
      to: AwsSDK.AutoScaling.Sandbox,
      as: :complete_lifecycle_action_response

    @doc false
    defdelegate sandbox_record_lifecycle_action_heartbeat_response(hook, asg, opts),
      to: AwsSDK.AutoScaling.Sandbox,
      as: :record_lifecycle_action_heartbeat_response

    @doc false
    defdelegate sandbox_set_instance_health_response(instance_id, health_status, opts),
      to: AwsSDK.AutoScaling.Sandbox,
      as: :set_instance_health_response

    @doc false
    defdelegate sandbox_terminate_instance_in_auto_scaling_group_response(
                  instance_id,
                  should_decrement,
                  opts
                ),
                to: AwsSDK.AutoScaling.Sandbox,
                as: :terminate_instance_in_auto_scaling_group_response

    @doc false
    defdelegate sandbox_set_desired_capacity_response(asg, desired, opts),
      to: AwsSDK.AutoScaling.Sandbox,
      as: :set_desired_capacity_response
  else
    @sandbox_unavailable "sandbox not available; add :sandbox_registry as a dep"

    defp sandbox_disabled?, do: false
    defp sandbox_describe_auto_scaling_groups_response(_o), do: raise(@sandbox_unavailable)
    defp sandbox_describe_auto_scaling_instances_response(_o), do: raise(@sandbox_unavailable)
    defp sandbox_describe_instance_refreshes_response(_a, _o), do: raise(@sandbox_unavailable)
    defp sandbox_describe_scaling_activities_response(_a, _o), do: raise(@sandbox_unavailable)
    defp sandbox_start_instance_refresh_response(_a, _o), do: raise(@sandbox_unavailable)
    defp sandbox_cancel_instance_refresh_response(_a, _o), do: raise(@sandbox_unavailable)
    defp sandbox_rollback_instance_refresh_response(_a, _o), do: raise(@sandbox_unavailable)

    defp sandbox_complete_lifecycle_action_response(_h, _a, _r, _o),
      do: raise(@sandbox_unavailable)

    defp sandbox_record_lifecycle_action_heartbeat_response(_h, _a, _o),
      do: raise(@sandbox_unavailable)

    defp sandbox_set_instance_health_response(_i, _h, _o), do: raise(@sandbox_unavailable)

    defp sandbox_terminate_instance_in_auto_scaling_group_response(_i, _d, _o),
      do: raise(@sandbox_unavailable)

    defp sandbox_set_desired_capacity_response(_a, _d, _o), do: raise(@sandbox_unavailable)
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
