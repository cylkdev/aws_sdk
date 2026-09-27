if Code.ensure_loaded?(SandboxRegistry) do
  defmodule AwsSDK.Logs.Sandbox do
    @moduledoc false

    @registry :aws_logs_sandbox

    alias AwsSDK.Sandbox

    def start_link, do: Sandbox.start_link(@registry)

    @spec disable_aws_logs_sandbox(map) :: :ok
    def disable_aws_logs_sandbox(_context), do: Sandbox.disable(@registry, __MODULE__)

    @spec sandbox_disabled? :: boolean
    def sandbox_disabled?, do: Sandbox.disabled?(@registry, __MODULE__)

    def create_log_group_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_log_group, name, binding)
    end

    def set_create_log_group_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_log_group, entries)
    end

    def delete_log_group_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_log_group, name, binding)
    end

    def set_delete_log_group_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_log_group, entries)
    end

    def describe_log_groups_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_log_groups, :*, binding)
    end

    def set_describe_log_groups_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_log_groups, entries)
    end

    def put_retention_policy_response(name, days, opts) do
      binding = [name: name, days: days, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :put_retention_policy, name, binding)
    end

    def set_put_retention_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :put_retention_policy, entries)
    end

    def delete_retention_policy_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_retention_policy, name, binding)
    end

    def set_delete_retention_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_retention_policy, entries)
    end

    def create_log_stream_response(group, stream, opts) do
      binding = [group: group, stream: stream, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_log_stream, group, binding)
    end

    def set_create_log_stream_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_log_stream, entries)
    end

    def delete_log_stream_response(group, stream, opts) do
      binding = [group: group, stream: stream, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_log_stream, group, binding)
    end

    def set_delete_log_stream_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_log_stream, entries)
    end

    def describe_log_streams_response(group, opts) do
      binding = [group: group, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_log_streams, group, binding)
    end

    def set_describe_log_streams_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_log_streams, entries)
    end

    def put_log_events_response(group, stream, events, opts) do
      binding = [group: group, stream: stream, events: events, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :put_log_events, group, binding)
    end

    def set_put_log_events_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :put_log_events, entries)
    end

    def get_log_events_response(group, stream, opts) do
      binding = [group: group, stream: stream, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_log_events, group, binding)
    end

    def set_get_log_events_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_log_events, entries)
    end

    def filter_log_events_response(group, opts) do
      binding = [group: group, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :filter_log_events, group, binding)
    end

    def set_filter_log_events_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :filter_log_events, entries)
    end

    def start_query_response(group, start_time, end_time, query, opts) do
      binding = [
        group: group,
        start_time: start_time,
        end_time: end_time,
        query: query,
        opts: opts
      ]

      Sandbox.apply(@registry, __MODULE__, :start_query, group, binding)
    end

    def set_start_query_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :start_query, entries)
    end

    def start_query_for_log_groups_response(groups, start_time, end_time, query, opts) do
      binding = [
        groups: groups,
        start_time: start_time,
        end_time: end_time,
        query: query,
        opts: opts
      ]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :start_query_for_log_groups,
        Enum.join(groups, ","),
        binding
      )
    end

    def set_start_query_for_log_groups_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :start_query_for_log_groups, entries)
    end

    def start_query_by_identifiers_response(identifiers, start_time, end_time, query, opts) do
      binding = [
        identifiers: identifiers,
        start_time: start_time,
        end_time: end_time,
        query: query,
        opts: opts
      ]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :start_query_by_identifiers,
        Enum.join(identifiers, ","),
        binding
      )
    end

    def set_start_query_by_identifiers_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :start_query_by_identifiers, entries)
    end

    def get_query_results_response(query_id, opts) do
      binding = [query_id: query_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_query_results, query_id, binding)
    end

    def set_get_query_results_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_query_results, entries)
    end

    def stop_query_response(query_id, opts) do
      binding = [query_id: query_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :stop_query, query_id, binding)
    end

    def set_stop_query_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :stop_query, entries)
    end
  end
end
