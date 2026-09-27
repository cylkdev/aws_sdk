if Code.ensure_loaded?(SandboxRegistry) do
  defmodule AwsSDK.ElasticLoadBalancingV2.Sandbox do
    @moduledoc false

    @registry :aws_elastic_load_balancing_v2_sandbox

    alias AwsSDK.Sandbox

    def start_link, do: Sandbox.start_link(@registry)

    @spec disable_aws_elastic_load_balancing_v2_sandbox(map) :: :ok
    def disable_aws_elastic_load_balancing_v2_sandbox(_context),
      do: Sandbox.disable(@registry, __MODULE__)

    @spec sandbox_disabled? :: boolean
    def sandbox_disabled?, do: Sandbox.disabled?(@registry, __MODULE__)

    def describe_target_groups_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_target_groups, :*, binding)
    end

    def set_describe_target_groups_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_target_groups, entries)
    end

    def describe_target_groups_by_names_response(names, opts) do
      binding = [names: names, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :describe_target_groups_by_names,
        Enum.join(names, ","),
        binding
      )
    end

    def set_describe_target_groups_by_names_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_target_groups_by_names, entries)
    end

    def describe_target_groups_by_arns_response(arns, opts) do
      binding = [arns: arns, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :describe_target_groups_by_arns,
        Enum.join(arns, ","),
        binding
      )
    end

    def set_describe_target_groups_by_arns_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_target_groups_by_arns, entries)
    end

    def describe_target_groups_by_load_balancer_response(load_balancer_arn, opts) do
      binding = [load_balancer_arn: load_balancer_arn, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :describe_target_groups_by_load_balancer,
        load_balancer_arn,
        binding
      )
    end

    def set_describe_target_groups_by_load_balancer_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_target_groups_by_load_balancer, entries)
    end

    def describe_target_health_response(target_group_arn, opts) do
      binding = [target_group_arn: target_group_arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_target_health, target_group_arn, binding)
    end

    def set_describe_target_health_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_target_health, entries)
    end

    def describe_load_balancers_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_load_balancers, :*, binding)
    end

    def set_describe_load_balancers_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_load_balancers, entries)
    end

    def describe_listeners_response(load_balancer_arn, opts) do
      binding = [load_balancer_arn: load_balancer_arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_listeners, load_balancer_arn, binding)
    end

    def set_describe_listeners_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_listeners, entries)
    end

    def describe_listeners_by_arns_response(listener_arns, opts) do
      binding = [listener_arns: listener_arns, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :describe_listeners_by_arns,
        Enum.join(listener_arns, ","),
        binding
      )
    end

    def set_describe_listeners_by_arns_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_listeners_by_arns, entries)
    end

    def describe_rules_response(listener_arn, opts) do
      binding = [listener_arn: listener_arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_rules, listener_arn, binding)
    end

    def set_describe_rules_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_rules, entries)
    end

    def describe_rules_by_arns_response(rule_arns, opts) do
      binding = [rule_arns: rule_arns, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :describe_rules_by_arns,
        Enum.join(rule_arns, ","),
        binding
      )
    end

    def set_describe_rules_by_arns_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_rules_by_arns, entries)
    end

    def modify_rule_response(rule_arn, actions, opts) do
      binding = [rule_arn: rule_arn, actions: actions, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :modify_rule, rule_arn, binding)
    end

    def set_modify_rule_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :modify_rule, entries)
    end

    def modify_listener_response(listener_arn, default_actions, opts) do
      binding = [listener_arn: listener_arn, default_actions: default_actions, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :modify_listener, listener_arn, binding)
    end

    def set_modify_listener_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :modify_listener, entries)
    end
  end
end
