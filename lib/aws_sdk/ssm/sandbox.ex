if Code.ensure_loaded?(SandboxRegistry) do
  defmodule AwsSDK.SSM.Sandbox do
    @moduledoc false

    @registry :aws_ssm_sandbox

    alias AwsSDK.Sandbox

    def start_link, do: Sandbox.start_link(@registry)

    @spec disable_aws_ssm_sandbox(map) :: :ok
    def disable_aws_ssm_sandbox(_context), do: Sandbox.disable(@registry, __MODULE__)

    @spec sandbox_disabled? :: boolean
    def sandbox_disabled?, do: Sandbox.disabled?(@registry, __MODULE__)

    def get_parameter_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_parameter, name, binding)
    end

    def set_get_parameter_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_parameter, entries)
    end

    def get_parameters_response(names, opts) do
      binding = [names: names, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_parameters, :*, binding)
    end

    def set_get_parameters_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_parameters, entries)
    end

    def get_parameters_by_path_response(path, opts) do
      binding = [path: path, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_parameters_by_path, path, binding)
    end

    def set_get_parameters_by_path_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_parameters_by_path, entries)
    end

    def put_parameter_response(name, value, opts) do
      binding = [name: name, value: value, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :put_parameter, name, binding)
    end

    def set_put_parameter_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :put_parameter, entries)
    end

    def delete_parameter_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_parameter, name, binding)
    end

    def set_delete_parameter_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_parameter, entries)
    end

    def delete_parameters_response(names, opts) do
      binding = [names: names, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_parameters, :*, binding)
    end

    def set_delete_parameters_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_parameters, entries)
    end

    def describe_parameters_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_parameters, :*, binding)
    end

    def set_describe_parameters_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_parameters, entries)
    end

    def describe_instance_information_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_instance_information, :*, binding)
    end

    def set_describe_instance_information_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_instance_information, entries)
    end

    def send_command_response(instance_ids, document_name, opts) do
      binding = [instance_ids: instance_ids, document_name: document_name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :send_command, :*, binding)
    end

    def set_send_command_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :send_command, entries)
    end

    def send_command_by_targets_response(targets, document_name, opts) do
      binding = [targets: targets, document_name: document_name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :send_command_by_targets, :*, binding)
    end

    def set_send_command_by_targets_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :send_command_by_targets, entries)
    end

    def get_command_invocation_response(command_id, instance_id, opts) do
      binding = [command_id: command_id, instance_id: instance_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_command_invocation, command_id, binding)
    end

    def set_get_command_invocation_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_command_invocation, entries)
    end

    def list_command_invocations_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_command_invocations, :*, binding)
    end

    def set_list_command_invocations_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_command_invocations, entries)
    end
  end
end
