defmodule AwsSDK.Credentials.Providers.LoginSessionTest do
  use ExUnit.Case, async: true

  alias AwsSDK.Credentials.Providers.LoginSession

  @tag :tmp_dir
  test "shells out to export-credentials and parses the JSON", %{tmp_dir: tmp} do
    script = Path.join(tmp, "fake-aws.sh")

    File.write!(
      script,
      ~S"""
      #!/bin/sh
      cat <<'JSON'
      {"Version":1,"AccessKeyId":"AKIA","SecretAccessKey":"SECRET","SessionToken":"TOKEN","Expiration":"2099-01-01T00:00:00Z"}
      JSON
      """
    )

    File.chmod!(script, 0o755)

    File.mkdir_p!(Path.join(tmp, ".aws"))

    File.write!(Path.join(tmp, ".aws/config"), """
    [profile dev]
    login_session = arn:aws:iam::123456789012:user/dev
    region = us-east-1
    """)

    assert {:ok,
            %{
              access_key_id: "AKIA",
              secret_access_key: "SECRET",
              security_token: "TOKEN",
              source: :login_session,
              expires_at: %DateTime{}
            }} =
             LoginSession.resolve(
               profile: "dev",
               home_dir: tmp,
               export_credentials_command: script
             )
  end

  @tag :tmp_dir
  test "skips when profile has no login_session key", %{tmp_dir: tmp} do
    File.mkdir_p!(Path.join(tmp, ".aws"))

    File.write!(Path.join(tmp, ".aws/config"), """
    [profile dev]
    region = us-east-1
    """)

    assert :skip = LoginSession.resolve(profile: "dev", home_dir: tmp)
  end

  @tag :tmp_dir
  test "skips when profile is absent", %{tmp_dir: tmp} do
    File.mkdir_p!(Path.join(tmp, ".aws"))

    assert :skip = LoginSession.resolve(profile: "missing", home_dir: tmp)
  end

  @tag :tmp_dir
  test "error when the export command exits non-zero", %{tmp_dir: tmp} do
    script = Path.join(tmp, "fail.sh")
    File.write!(script, "#!/bin/sh\nexit 9\n")
    File.chmod!(script, 0o755)

    File.mkdir_p!(Path.join(tmp, ".aws"))

    File.write!(Path.join(tmp, ".aws/config"), """
    [profile dev]
    login_session = arn:aws:iam::123456789012:user/dev
    """)

    assert {:error, {:credential_process_failed, 9, _}} =
             LoginSession.resolve(
               profile: "dev",
               home_dir: tmp,
               export_credentials_command: script
             )
  end

  @tag :tmp_dir
  test "error when the export command emits a wrong JSON version", %{tmp_dir: tmp} do
    script = Path.join(tmp, "bad-version.sh")

    File.write!(script, ~S"""
    #!/bin/sh
    echo '{"Version":2,"AccessKeyId":"A","SecretAccessKey":"S"}'
    """)

    File.chmod!(script, 0o755)

    File.mkdir_p!(Path.join(tmp, ".aws"))

    File.write!(Path.join(tmp, ".aws/config"), """
    [profile dev]
    login_session = arn:aws:iam::123456789012:user/dev
    """)

    assert {:error, {:credential_process_invalid, {:unsupported_version, 2}}} =
             LoginSession.resolve(
               profile: "dev",
               home_dir: tmp,
               export_credentials_command: script
             )
  end
end
