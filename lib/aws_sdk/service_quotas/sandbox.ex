if Code.ensure_loaded?(SandboxRegistry) do
  defmodule AwsSDK.ServiceQuotas.Sandbox do
    @moduledoc false

    @registry :aws_service_quotas_sandbox

    alias AwsSDK.Sandbox

    def start_link, do: Sandbox.start_link(@registry)

    @spec disable_aws_service_quotas_sandbox(map) :: :ok
    def disable_aws_service_quotas_sandbox(_context), do: Sandbox.disable(@registry, __MODULE__)

    @spec sandbox_disabled? :: boolean
    def sandbox_disabled?, do: Sandbox.disabled?(@registry, __MODULE__)

    def get_service_quota_response(service_code, quota_code, opts) do
      binding = [service_code: service_code, quota_code: quota_code, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_service_quota, quota_code, binding)
    end

    def set_get_service_quota_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_service_quota, entries)
    end
  end
end
