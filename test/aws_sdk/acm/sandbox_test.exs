defmodule AwsSDK.ACM.SandboxTest do
  use ExUnit.Case, async: true

  alias AwsSDK.ACM
  alias AwsSDK.ACM.Sandbox

  describe "list_certificates/1" do
    test "returns the registered response" do
      response =
        {:ok, %{body: %{certificate_summary_list: [], next_token: nil}, headers: %{}}}

      Sandbox.set_list_certificates_responses([fn -> response end])

      assert response === ACM.list_certificates(sandbox: [enabled: true])
    end
  end
end
