defmodule AwsSDK.ACMTest do
  use ExUnit.Case, async: true

  alias AwsSDK.ACM

  @opts [profile: "aws-sandbox", region: "us-east-2"]

  describe "describe_certificate/2" do
    test "a requested certificate waits for validation with the domain and key asked for" do
      domain_name = "aws-sdk-acm-test-describe-certificate.cylk.dev"

      {:ok, requested} =
        ACM.request_certificate(
          domain_name,
          [validation_method: "DNS", key_algorithm: "RSA_2048"] ++ @opts
        )

      # ACM fills in the domain and key a moment after the request returns.
      described =
        fn ->
          Process.sleep(1000)
          {:ok, described} = ACM.describe_certificate(requested.body.certificate_arn, @opts)
          described
        end
        |> Stream.repeatedly()
        |> Enum.find(fn described -> Map.has_key?(described.body.certificate, :domain_name) end)

      {:ok, _deleted} = ACM.delete_certificate(requested.body.certificate_arn, @opts)

      certificate = described.body.certificate

      assert {domain_name, "RSA-2048", "PENDING_VALIDATION"} ===
               {certificate.domain_name, certificate.key_algorithm, certificate.status}
    end
  end
end
