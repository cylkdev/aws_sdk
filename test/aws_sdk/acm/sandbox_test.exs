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

  describe "request_certificate/2" do
    test "keys off the domain name" do
      response = {:ok, %{body: %{certificate_arn: "arn:cert/1"}, headers: %{}}}

      Sandbox.set_request_certificate_responses([{"example.com", fn -> response end}])

      assert response === ACM.request_certificate("example.com", sandbox: [enabled: true])
    end
  end

  describe "delete_certificate/2" do
    test "keys off the certificate arn" do
      response = {:ok, %{body: %{}, headers: %{}}}

      Sandbox.set_delete_certificate_responses([{"arn:cert/1", fn -> response end}])

      assert response === ACM.delete_certificate("arn:cert/1", sandbox: [enabled: true])
    end
  end
end
