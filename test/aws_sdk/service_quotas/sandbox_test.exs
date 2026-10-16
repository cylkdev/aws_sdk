defmodule AwsSDK.ServiceQuotas.SandboxTest do
  use ExUnit.Case, async: true

  alias AwsSDK.ServiceQuotas
  alias AwsSDK.ServiceQuotas.Sandbox

  describe "get_service_quota/3" do
    test "returns the response registered for the quota code" do
      response = {:ok, %{body: %{quota: %{quota_code: "L-1216C47A", value: 5.0}}, headers: %{}}}

      Sandbox.set_get_service_quota_responses([{"L-1216C47A", fn -> response end}])

      assert response ===
               ServiceQuotas.get_service_quota("ec2", "L-1216C47A", sandbox: [enabled: true])
    end
  end
end
