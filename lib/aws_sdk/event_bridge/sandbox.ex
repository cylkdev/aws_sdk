if Code.ensure_loaded?(SandboxRegistry) do
  defmodule AwsSDK.EventBridge.Sandbox do
    @moduledoc false

    @registry :aws_event_bridge_sandbox

    alias AwsSDK.Sandbox

    def start_link, do: Sandbox.start_link(@registry)

    @spec disable_aws_event_bridge_sandbox(map) :: :ok
    def disable_aws_event_bridge_sandbox(_context),
      do: Sandbox.disable(@registry, __MODULE__)

    @spec sandbox_disabled? :: boolean
    def sandbox_disabled?, do: Sandbox.disabled?(@registry, __MODULE__)

    def put_rule_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :put_rule, name, binding)
    end

    def set_put_rule_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :put_rule, entries)
    end

    def describe_rule_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_rule, name, binding)
    end

    def set_describe_rule_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_rule, entries)
    end

    def list_rules_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_rules, :*, binding)
    end

    def set_list_rules_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_rules, entries)
    end

    def delete_rule_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_rule, name, binding)
    end

    def set_delete_rule_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_rule, entries)
    end

    def put_targets_response(rule, targets, opts) do
      binding = [rule: rule, targets: targets, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :put_targets, rule, binding)
    end

    def set_put_targets_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :put_targets, entries)
    end

    def list_targets_by_rule_response(rule, opts) do
      binding = [rule: rule, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_targets_by_rule, rule, binding)
    end

    def set_list_targets_by_rule_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_targets_by_rule, entries)
    end

    def remove_targets_response(rule, ids, opts) do
      binding = [rule: rule, ids: ids, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :remove_targets, rule, binding)
    end

    def set_remove_targets_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :remove_targets, entries)
    end

    def create_connection_response(name, authorization_type, auth_parameters, opts) do
      binding = [
        name: name,
        authorization_type: authorization_type,
        auth_parameters: auth_parameters,
        opts: opts
      ]

      Sandbox.apply(@registry, __MODULE__, :create_connection, name, binding)
    end

    def set_create_connection_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_connection, entries)
    end

    def describe_connection_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_connection, name, binding)
    end

    def set_describe_connection_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_connection, entries)
    end

    def update_connection_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :update_connection, name, binding)
    end

    def set_update_connection_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :update_connection, entries)
    end

    def delete_connection_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_connection, name, binding)
    end

    def set_delete_connection_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_connection, entries)
    end

    def list_connections_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_connections, :*, binding)
    end

    def set_list_connections_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_connections, entries)
    end

    def create_api_destination_response(
          name,
          connection_arn,
          invocation_endpoint,
          http_method,
          opts
        ) do
      binding = [
        name: name,
        connection_arn: connection_arn,
        invocation_endpoint: invocation_endpoint,
        http_method: http_method,
        opts: opts
      ]

      Sandbox.apply(@registry, __MODULE__, :create_api_destination, name, binding)
    end

    def set_create_api_destination_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_api_destination, entries)
    end

    def describe_api_destination_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_api_destination, name, binding)
    end

    def set_describe_api_destination_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_api_destination, entries)
    end

    def update_api_destination_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :update_api_destination, name, binding)
    end

    def set_update_api_destination_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :update_api_destination, entries)
    end

    def delete_api_destination_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_api_destination, name, binding)
    end

    def set_delete_api_destination_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_api_destination, entries)
    end

    def list_api_destinations_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_api_destinations, :*, binding)
    end

    def set_list_api_destinations_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_api_destinations, entries)
    end

    def create_event_bus_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_event_bus, name, binding)
    end

    def set_create_event_bus_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_event_bus, entries)
    end

    def describe_event_bus_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_event_bus, name, binding)
    end

    def set_describe_event_bus_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_event_bus, entries)
    end

    def delete_event_bus_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_event_bus, name, binding)
    end

    def set_delete_event_bus_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_event_bus, entries)
    end

    def list_event_buses_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_event_buses, :*, binding)
    end

    def set_list_event_buses_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_event_buses, entries)
    end

    def put_events_response(entries, opts) do
      binding = [entries: entries, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :put_events, :*, binding)
    end

    def set_put_events_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :put_events, entries)
    end

    def enable_rule_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :enable_rule, name, binding)
    end

    def set_enable_rule_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :enable_rule, entries)
    end

    def disable_rule_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :disable_rule, name, binding)
    end

    def set_disable_rule_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :disable_rule, entries)
    end
  end
end
