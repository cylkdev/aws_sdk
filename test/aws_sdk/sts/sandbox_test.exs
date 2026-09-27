defmodule AwsSDK.STS.SandboxTest do
  use ExUnit.Case, async: true

  alias AwsSDK.STS
  alias AwsSDK.STS.Sandbox

  describe "get_caller_identity/1" do
    test "returns the registered identity" do
      Sandbox.set_get_caller_identity_responses([
        fn ->
          {:ok,
           %{
             account: "123456789012",
             arn: "arn:aws:iam::123456789012:user/alice",
             user_id: "AIDA123"
           }}
        end
      ])

      assert {:ok,
              %{
                account: "123456789012",
                arn: "arn:aws:iam::123456789012:user/alice",
                user_id: "AIDA123"
              }} = STS.get_caller_identity(sandbox: [enabled: true])
    end

    test "returns the registered error" do
      Sandbox.set_get_caller_identity_responses([fn -> {:error, :boom} end])

      assert {:error, :boom} = STS.get_caller_identity(sandbox: [enabled: true])
    end
  end
end
