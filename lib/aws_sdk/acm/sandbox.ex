if Code.ensure_loaded?(SandboxRegistry) do
  defmodule AwsSDK.ACM.Sandbox do
    @moduledoc false

    @registry :aws_acm_sandbox

    alias AwsSDK.Sandbox

    def start_link, do: Sandbox.start_link(@registry)

    @spec disable_aws_acm_sandbox(map) :: :ok
    def disable_aws_acm_sandbox(_context), do: Sandbox.disable(@registry, __MODULE__)

    @spec sandbox_disabled? :: boolean
    def sandbox_disabled?, do: Sandbox.disabled?(@registry, __MODULE__)

    def list_certificates_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_certificates, :*, binding)
    end

    def set_list_certificates_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_certificates, entries)
    end
  end
end
