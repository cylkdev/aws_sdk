defmodule AwsSDK.Credentials.SecretsTest do
  use ExUnit.Case, async: true

  alias AwsSDK.Credentials.Secrets

  test "removes secret keys whatever their case or type, and keeps everything else" do
    facts = %{
      "AccessKeyId" => "AKIA",
      "SecretAccessKey" => "s",
      "Token" => "t",
      body: %{"roleCredentials" => %{"accessKeyId" => "AKIA", "sessionToken" => "t"}},
      token_cache_read: %{"accessToken" => "a", "refreshToken" => "r", "clientSecret" => "c"},
      profile: %{"aws_secret_access_key" => "s", "region" => "eu-west-1"},
      process: %{stdout: "{\"SecretAccessKey\":\"s\"}", stderr: "", exit_status: 0},
      headers: [{"x-aws-ec2-metadata-token", "imds"}, {"content-type", "text/plain"}],
      result: {:ok, %{secret_access_key: "s", source: :env}}
    }

    assert Secrets.strip(facts) == %{
             "AccessKeyId" => "AKIA",
             body: %{"roleCredentials" => %{"accessKeyId" => "AKIA"}},
             token_cache_read: %{},
             profile: %{"region" => "eu-west-1"},
             process: %{stderr: "", exit_status: 0},
             headers: [{"x-aws-ec2-metadata-token", nil}, {"content-type", "text/plain"}],
             result: {:ok, %{source: :env}}
           }
  end
end
