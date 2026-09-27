defmodule AwsSDK.Credentials.Providers.CredentialProcessTest do
  use ExUnit.Case, async: true

  alias AwsSDK.Credentials.Providers.CredentialProcess

  @tag :tmp_dir
  test "runs the command and parses its JSON output", %{tmp_dir: tmp} do
    script = Path.join(tmp, "cred.sh")

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
    credential_process = #{script}
    """)

    assert {:ok,
            %{
              access_key_id: "AKIA",
              secret_access_key: "SECRET",
              security_token: "TOKEN",
              source: :credential_process,
              expires_at: %DateTime{}
            }} = CredentialProcess.resolve(profile: "dev", home_dir: tmp)
  end

  @tag :tmp_dir
  test "skip when profile has no credential_process key", %{tmp_dir: tmp} do
    File.mkdir_p!(Path.join(tmp, ".aws"))

    File.write!(Path.join(tmp, ".aws/config"), """
    [profile dev]
    region = us-east-1
    """)

    assert :skip = CredentialProcess.resolve(profile: "dev", home_dir: tmp)
  end

  @tag :tmp_dir
  test "error when command fails with non-zero status", %{tmp_dir: tmp} do
    script = Path.join(tmp, "fail.sh")
    File.write!(script, "#!/bin/sh\nexit 7\n")
    File.chmod!(script, 0o755)

    File.mkdir_p!(Path.join(tmp, ".aws"))

    File.write!(Path.join(tmp, ".aws/config"), """
    [profile dev]
    credential_process = #{script}
    """)

    assert {:error, {:credential_process_failed, 7, _}} =
             CredentialProcess.resolve(profile: "dev", home_dir: tmp)
  end

  @tag :tmp_dir
  test "error when JSON output has wrong version", %{tmp_dir: tmp} do
    script = Path.join(tmp, "bad.sh")

    File.write!(script, ~S"""
    #!/bin/sh
    echo '{"Version":2,"AccessKeyId":"A","SecretAccessKey":"S"}'
    """)

    File.chmod!(script, 0o755)

    File.mkdir_p!(Path.join(tmp, ".aws"))

    File.write!(Path.join(tmp, ".aws/config"), """
    [profile dev]
    credential_process = #{script}
    """)

    assert {:error, {:credential_process_invalid, {:unsupported_version, 2}}} =
             CredentialProcess.resolve(profile: "dev", home_dir: tmp)
  end
end
