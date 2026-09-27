defmodule AwsSDK.Credentials.SSO.TokenCacheTest do
  use ExUnit.Case, async: true

  alias AwsSDK.Credentials.SSO.TokenCache

  @tag :tmp_dir
  test "path/2 hashes the key with sha1-hex", %{tmp_dir: tmp} do
    assert Path.join(tmp, ".aws/sso/cache/b28b7af69320201d1cf206ebf28373980add1451.json") ===
             TokenCache.path("main", home_dir: tmp)
  end

  @tag :tmp_dir
  test "read/2 returns the contents that were written", %{tmp_dir: tmp} do
    :ok = TokenCache.write("main", %{"accessToken" => "abc"}, home_dir: tmp)

    assert {:ok, %{"accessToken" => "abc"}} = TokenCache.read("main", home_dir: tmp)
  end

  @tag :tmp_dir
  test "read/2 returns {:error, :enoent} when the file is missing", %{tmp_dir: tmp} do
    assert {:error, :enoent} = TokenCache.read("absent", home_dir: tmp)
  end

  @tag :tmp_dir
  test "write/3 replaces the cache file and restricts it to the owner", %{tmp_dir: tmp} do
    assert :ok = TokenCache.write("main", %{"accessToken" => "v1"}, home_dir: tmp)
    assert {:ok, %{"accessToken" => "v1"}} = TokenCache.read("main", home_dir: tmp)

    assert 0o600 ===
             Bitwise.band(File.stat!(TokenCache.path("main", home_dir: tmp)).mode, 0o777)

    assert :ok = TokenCache.write("main", %{"accessToken" => "v2"}, home_dir: tmp)
    assert {:ok, %{"accessToken" => "v2"}} = TokenCache.read("main", home_dir: tmp)
  end

  @tag :tmp_dir
  test "write/3 returns an error tuple when the cache directory cannot be created",
       %{tmp_dir: tmp} do
    File.write!(Path.join(tmp, ".aws"), "")

    assert {:error, :enotdir} = TokenCache.write("main", %{"accessToken" => "v1"}, home_dir: tmp)
  end
end
