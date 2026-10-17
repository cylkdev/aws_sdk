defmodule AwsSDK.Credentials.INITest do
  use ExUnit.Case, async: true

  alias AwsSDK.Credentials.INI

  describe "parse/1" do
    test "returns every section keyed by header" do
      contents = """
      [default]
      aws_access_key_id = AKIADEFAULT
      aws_secret_access_key = default-secret

      [foo]
      aws_access_key_id = AKIAFOO
      """

      assert %{
               "default" => %{
                 "aws_access_key_id" => "AKIADEFAULT",
                 "aws_secret_access_key" => "default-secret"
               },
               "foo" => %{"aws_access_key_id" => "AKIAFOO"}
             } === INI.parse(contents)
    end

    test "strips inline comments and trims whitespace" do
      contents = """
      [profile foo]
        region = us-east-1 # primary region
        sso_session = main
      """

      assert %{"profile foo" => %{"region" => "us-east-1", "sso_session" => "main"}} ===
               INI.parse(contents)
    end

    test "ignores orphan key=value pairs before the first header" do
      contents = """
      stray = line
      [default]
      key = value
      """

      assert %{"default" => %{"key" => "value"}} === INI.parse(contents)
    end

    test "preserves section names with spaces" do
      contents = """
      [sso-session my-session]
      sso_region = us-east-1
      """

      assert %{"sso-session my-session" => %{"sso_region" => "us-east-1"}} ===
               INI.parse(contents)
    end

    test "ignores full-line comments" do
      contents = """
      # top-level comment
      [default]
      # in-section comment
      key = value
      """

      assert %{"default" => %{"key" => "value"}} === INI.parse(contents)
    end
  end

  describe "read/1" do
    @tag :tmp_dir
    test "returns {:ok, sections} for an existing file", %{tmp_dir: tmp} do
      path = Path.join(tmp, "creds")
      File.write!(path, "[default]\nkey = v\n")
      assert {:ok, %{"default" => %{"key" => "v"}}} = INI.read(path)
    end

    test "returns a file error for a missing file" do
      path = "/nonexistent/aws/credentials-#{System.unique_integer()}"

      assert {:error,
              %ErrorMessage{
                code: :internal_server_error,
                message: "internal server error",
                details: %{kind: :file_error, reason: :enoent, path: path}
              }} === INI.read(path)
    end
  end
end
