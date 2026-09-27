if Code.ensure_loaded?(SandboxRegistry) do
  defmodule AwsSDK.AutoScaling.Sandbox do
    @moduledoc false

    @registry :aws_auto_scaling_sandbox

    alias AwsSDK.Sandbox

    def start_link, do: Sandbox.start_link(@registry)

    @spec disable_aws_auto_scaling_sandbox(map) :: :ok
    def disable_aws_auto_scaling_sandbox(_context),
      do: Sandbox.disable(@registry, __MODULE__)

    @spec sandbox_disabled? :: boolean
    def sandbox_disabled?, do: Sandbox.disabled?(@registry, __MODULE__)

    def describe_auto_scaling_groups_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :describe_auto_scaling_groups,
        slot_filter_value(opts[:filters]) || :*,
        binding
      )
    end

    # A describe narrowed to one slot names it in a `tag:Slot` filter; a
    # describe of every slot of a service does not. Keying on that value lets
    # a caller register one reply per slot and another for the unfiltered
    # read, the way `create_auto_scaling_group` keys on the group it is given.
    defp slot_filter_value(filters) when is_list(filters) do
      Enum.find_value(filters, fn
        %{name: "tag:Slot", values: [value | _rest]} -> value
        _filter -> nil
      end)
    end

    defp slot_filter_value(_filters), do: nil

    def set_describe_auto_scaling_groups_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_auto_scaling_groups, entries)
    end

    def describe_auto_scaling_instances_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_auto_scaling_instances, :*, binding)
    end

    def set_describe_auto_scaling_instances_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_auto_scaling_instances, entries)
    end

    def describe_instance_refreshes_response(asg, opts) do
      binding = [asg: asg, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_instance_refreshes, asg, binding)
    end

    def set_describe_instance_refreshes_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_instance_refreshes, entries)
    end

    def describe_scaling_activities_response(asg, opts) do
      binding = [asg: asg, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_scaling_activities, asg, binding)
    end

    def set_describe_scaling_activities_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_scaling_activities, entries)
    end

    def start_instance_refresh_response(asg, opts) do
      binding = [asg: asg, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :start_instance_refresh, asg, binding)
    end

    def set_start_instance_refresh_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :start_instance_refresh, entries)
    end

    def cancel_instance_refresh_response(asg, opts) do
      binding = [asg: asg, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :cancel_instance_refresh, asg, binding)
    end

    def set_cancel_instance_refresh_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :cancel_instance_refresh, entries)
    end

    def rollback_instance_refresh_response(asg, opts) do
      binding = [asg: asg, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :rollback_instance_refresh, asg, binding)
    end

    def set_rollback_instance_refresh_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :rollback_instance_refresh, entries)
    end

    def complete_lifecycle_action_response(hook, asg, result, opts) do
      binding = [hook: hook, asg: asg, result: result, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :complete_lifecycle_action, "#{hook}|#{asg}", binding)
    end

    def set_complete_lifecycle_action_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :complete_lifecycle_action, entries)
    end

    def record_lifecycle_action_heartbeat_response(hook, asg, opts) do
      binding = [hook: hook, asg: asg, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :record_lifecycle_action_heartbeat,
        "#{hook}|#{asg}",
        binding
      )
    end

    def set_record_lifecycle_action_heartbeat_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :record_lifecycle_action_heartbeat, entries)
    end

    def set_instance_health_response(instance_id, health_status, opts) do
      binding = [instance_id: instance_id, health_status: health_status, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :set_instance_health, instance_id, binding)
    end

    def set_set_instance_health_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :set_instance_health, entries)
    end

    def terminate_instance_in_auto_scaling_group_response(instance_id, should_decrement, opts) do
      binding = [instance_id: instance_id, should_decrement: should_decrement, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :terminate_instance_in_auto_scaling_group,
        instance_id,
        binding
      )
    end

    def set_terminate_instance_in_auto_scaling_group_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :terminate_instance_in_auto_scaling_group, entries)
    end

    def set_desired_capacity_response(asg, desired_capacity, opts) do
      binding = [asg: asg, desired_capacity: desired_capacity, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :set_desired_capacity, asg, binding)
    end

    def set_set_desired_capacity_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :set_desired_capacity, entries)
    end
  end
end
