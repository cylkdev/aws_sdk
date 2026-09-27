defmodule AwsSDK.Credentials.ProfileTest do
  use ExUnit.Case

  alias AwsSDK.Credentials.Profile

  describe "load/2" do
    @tag :tmp_dir
    test "merges ~/.aws/config and ~/.aws/credentials for the default profile", %{tmp_dir: tmp} do
      File.mkdir_p!(Path.join(tmp, ".aws"))

      File.write!(Path.join(tmp, ".aws/config"), """
      [default]
      region = us-east-2
      """)

      File.write!(Path.join(tmp, ".aws/credentials"), """
      [default]
      aws_access_key_id = AKIA
      aws_secret_access_key = SECRET
      """)

      assert %{
               "region" => "us-east-2",
               "aws_access_key_id" => "AKIA",
               "aws_secret_access_key" => "SECRET"
             } === Profile.load("default", home_dir: tmp)
    end

    @tag :tmp_dir
    test "reads [profile NAME] for non-default profiles in ~/.aws/config", %{tmp_dir: tmp} do
      File.mkdir_p!(Path.join(tmp, ".aws"))

      File.write!(Path.join(tmp, ".aws/config"), """
      [profile dev]
      region = us-west-2
      sso_session = main
      """)

      assert %{"region" => "us-west-2", "sso_session" => "main"} ===
               Profile.load("dev", home_dir: tmp)
    end

    @tag :tmp_dir
    test "credentials file wins when both files define the same key", %{tmp_dir: tmp} do
      File.mkdir_p!(Path.join(tmp, ".aws"))

      File.write!(Path.join(tmp, ".aws/config"), """
      [profile dev]
      aws_access_key_id = FROM_CONFIG
      """)

      File.write!(Path.join(tmp, ".aws/credentials"), """
      [dev]
      aws_access_key_id = FROM_CREDENTIALS
      """)

      assert %{"aws_access_key_id" => "FROM_CREDENTIALS"} = Profile.load("dev", home_dir: tmp)
    end

    @tag :tmp_dir
    test "returns nil when the profile is absent from both files", %{tmp_dir: tmp} do
      File.mkdir_p!(Path.join(tmp, ".aws"))
      File.write!(Path.join(tmp, ".aws/config"), "[default]\n")
      assert nil === Profile.load("missing", home_dir: tmp)
    end
  end

  describe "load_sso_session/2" do
    @tag :tmp_dir
    test "returns sso-session blocks from ~/.aws/config", %{tmp_dir: tmp} do
      File.mkdir_p!(Path.join(tmp, ".aws"))

      File.write!(Path.join(tmp, ".aws/config"), """
      [sso-session main]
      sso_start_url = https://example.awsapps.com/start
      sso_region = us-east-1
      sso_registration_scopes = sso:account:access
      """)

      assert %{
               "sso_start_url" => "https://example.awsapps.com/start",
               "sso_region" => "us-east-1",
               "sso_registration_scopes" => "sso:account:access"
             } === Profile.load_sso_session("main", home_dir: tmp)
    end

    @tag :tmp_dir
    test "returns nil when the session does not exist", %{tmp_dir: tmp} do
      File.mkdir_p!(Path.join(tmp, ".aws"))
      File.write!(Path.join(tmp, ".aws/config"), "")
      assert nil === Profile.load_sso_session("missing", home_dir: tmp)
    end
  end

  describe "default/0" do
    test "prefers AWS_PROFILE, then AWS_DEFAULT_PROFILE, then \"default\"" do
      System.delete_env("AWS_PROFILE")
      System.delete_env("AWS_DEFAULT_PROFILE")
      assert "default" === Profile.default()

      System.put_env("AWS_DEFAULT_PROFILE", "fallback")
      assert "fallback" === Profile.default()

      System.put_env("AWS_PROFILE", "primary")
      assert "primary" === Profile.default()
    after
      System.delete_env("AWS_PROFILE")
      System.delete_env("AWS_DEFAULT_PROFILE")
    end
  end
end
