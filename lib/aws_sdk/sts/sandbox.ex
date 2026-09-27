if Code.ensure_loaded?(SandboxRegistry) do
  defmodule AwsSDK.STS.Sandbox do
    @moduledoc false

    @registry :aws_sts_sandbox

    alias AwsSDK.Sandbox

    def start_link, do: Sandbox.start_link(@registry)

    @spec disable_aws_sts_sandbox(map) :: :ok
    def disable_aws_sts_sandbox(_context), do: Sandbox.disable(@registry, __MODULE__)

    @spec sandbox_disabled? :: boolean
    def sandbox_disabled?, do: Sandbox.disabled?(@registry, __MODULE__)

    def get_caller_identity_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_caller_identity, :*, binding)
    end

    def set_get_caller_identity_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_caller_identity, entries)
    end
  end
end
