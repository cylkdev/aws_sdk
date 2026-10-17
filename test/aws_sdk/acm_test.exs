defmodule AwsSDK.ACMTest do
  use ExUnit.Case, async: true

  alias AwsSDK.ACM

  describe "list_certificates/1" do
    test "key_types lists certificates whose key is not RSA_2048" do
      {:ok, response} =
        ACM.list_certificates(
          profile: "aws-sandbox",
          region: "us-east-2",
          certificate_statuses: ["ISSUED"],
          key_types: ["RSA_4096"]
        )

      domain_names =
        Enum.map(response.body.certificate_summary_list, fn summary ->
          {summary.domain_name, summary.key_algorithm}
        end)

      assert [{"mcp.cylk.dev", "RSA-4096"}] === domain_names
    end
  end
end
