defmodule AwsSDK.IAM.SandboxTest do
  use ExUnit.Case, async: true

  alias AwsSDK.IAM
  alias AwsSDK.IAM.Sandbox

  # Users

  describe "create_user/2" do
    test "returns mocked success" do
      Sandbox.set_create_user_responses([
        {"alice",
         fn -> {:ok, %{user: %{user_name: "alice", arn: "arn:aws:iam::123:user/alice"}}} end}
      ])

      assert {:ok, %{user: %{user_name: "alice"}}} =
               IAM.create_user("alice", sandbox: [enabled: true])
    end
  end

  describe "get_user/1" do
    test "returns mocked success" do
      Sandbox.set_get_user_responses([
        fn -> {:ok, %{user: %{user_name: "alice", user_id: "AIDA123"}}} end
      ])

      assert {:ok, %{user: %{user_id: "AIDA123"}}} =
               IAM.get_user(user_name: "alice", sandbox: [enabled: true])
    end
  end

  describe "list_users/1" do
    test "returns mocked list" do
      Sandbox.set_list_users_responses([
        fn -> {:ok, %{users: [%{user_name: "alice"}], is_truncated: false, marker: nil}} end
      ])

      assert {:ok, %{users: [%{user_name: "alice"}], is_truncated: false}} =
               IAM.list_users(sandbox: [enabled: true])
    end
  end

  describe "delete_user/2" do
    test "returns mocked success" do
      Sandbox.set_delete_user_responses([
        {"alice", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} = IAM.delete_user("alice", sandbox: [enabled: true])
    end
  end

  # Access Keys

  describe "create_access_key/1" do
    test "returns mocked success" do
      Sandbox.set_create_access_key_responses([
        fn ->
          {:ok, %{access_key: %{access_key_id: "AKIA123", secret_access_key: "secret"}}}
        end
      ])

      assert {:ok, %{access_key: %{access_key_id: "AKIA123", secret_access_key: "secret"}}} =
               IAM.create_access_key(user_name: "alice", sandbox: [enabled: true])
    end
  end

  describe "list_access_keys/1" do
    test "returns mocked list" do
      Sandbox.set_list_access_keys_responses([
        fn -> {:ok, %{access_key_metadata: [%{access_key_id: "AKIA123", status: "Active"}]}} end
      ])

      assert {:ok, %{access_key_metadata: [%{access_key_id: "AKIA123"}]}} =
               IAM.list_access_keys(user_name: "alice", sandbox: [enabled: true])
    end
  end

  describe "delete_access_key/2" do
    test "returns mocked success" do
      Sandbox.set_delete_access_key_responses([
        {"AKIA123", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.delete_access_key("AKIA123", user_name: "alice", sandbox: [enabled: true])
    end
  end

  # Groups

  describe "create_group/2" do
    test "returns mocked success" do
      Sandbox.set_create_group_responses([
        {"devs",
         fn -> {:ok, %{group: %{group_name: "devs", arn: "arn:aws:iam::123:group/devs"}}} end}
      ])

      assert {:ok, %{group: %{group_name: "devs"}}} =
               IAM.create_group("devs", sandbox: [enabled: true])
    end
  end

  describe "list_groups/1" do
    test "returns mocked list" do
      Sandbox.set_list_groups_responses([
        fn -> {:ok, %{groups: [%{group_name: "devs"}]}} end
      ])

      assert {:ok, %{groups: [%{group_name: "devs"}]}} = IAM.list_groups(sandbox: [enabled: true])
    end
  end

  describe "delete_group/2" do
    test "returns mocked success" do
      Sandbox.set_delete_group_responses([
        {"devs", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} = IAM.delete_group("devs", sandbox: [enabled: true])
    end
  end

  # Group membership

  describe "add_user_to_group/3" do
    test "returns mocked success" do
      Sandbox.set_add_user_to_group_responses([
        {"devs", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} = IAM.add_user_to_group("devs", "alice", sandbox: [enabled: true])
    end
  end

  describe "remove_user_from_group/3" do
    test "returns mocked success" do
      Sandbox.set_remove_user_from_group_responses([
        {"devs", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} = IAM.remove_user_from_group("devs", "alice", sandbox: [enabled: true])
    end
  end

  # Roles

  describe "create_role/3" do
    test "returns mocked success" do
      Sandbox.set_create_role_responses([
        {"AdminRole", fn -> {:ok, %{role: %{role_name: "AdminRole", role_id: "AROA123"}}} end}
      ])

      trust_policy = %{"Version" => "2012-10-17", "Statement" => []}

      assert {:ok, %{role: %{role_name: "AdminRole"}}} =
               IAM.create_role("AdminRole", trust_policy, sandbox: [enabled: true])
    end
  end

  describe "get_role/2" do
    test "returns mocked success" do
      Sandbox.set_get_role_responses([
        {"AdminRole",
         fn ->
           {:ok, %{role: %{role_name: "AdminRole", arn: "arn:aws:iam::123:role/AdminRole"}}}
         end}
      ])

      assert {:ok, %{role: %{role_name: "AdminRole"}}} =
               IAM.get_role("AdminRole", sandbox: [enabled: true])
    end
  end

  describe "list_roles/1" do
    test "returns mocked list" do
      Sandbox.set_list_roles_responses([
        fn -> {:ok, %{roles: [%{role_name: "AdminRole"}]}} end
      ])

      assert {:ok, %{roles: [%{role_name: "AdminRole"}]}} =
               IAM.list_roles(sandbox: [enabled: true])
    end
  end

  describe "delete_role/2" do
    test "returns mocked success" do
      Sandbox.set_delete_role_responses([
        {"AdminRole", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} = IAM.delete_role("AdminRole", sandbox: [enabled: true])
    end
  end

  # Policies

  describe "create_policy/3" do
    test "returns mocked success" do
      Sandbox.set_create_policy_responses([
        {"ReadOnly", fn -> {:ok, %{policy: %{policy_name: "ReadOnly", policy_id: "ANPA123"}}} end}
      ])

      policy_doc = %{"Version" => "2012-10-17", "Statement" => []}

      assert {:ok, %{policy: %{policy_name: "ReadOnly"}}} =
               IAM.create_policy("ReadOnly", policy_doc, sandbox: [enabled: true])
    end
  end

  describe "get_policy/2" do
    test "returns mocked success" do
      Sandbox.set_get_policy_responses([
        {"arn:aws:iam::123:policy/ReadOnly",
         fn -> {:ok, %{policy: %{policy_name: "ReadOnly", default_version_id: "v1"}}} end}
      ])

      assert {:ok, %{policy: %{policy_name: "ReadOnly"}}} =
               IAM.get_policy("arn:aws:iam::123:policy/ReadOnly", sandbox: [enabled: true])
    end
  end

  describe "get_policy_version/3" do
    test "returns mocked success" do
      Sandbox.set_get_policy_version_responses([
        {"arn:aws:iam::123:policy/ReadOnly",
         fn ->
           {:ok,
            %{
              policy_version: %{
                document: %{"Version" => "2012-10-17"},
                version_id: "v1",
                is_default_version: true
              }
            }}
         end}
      ])

      assert {:ok, %{policy_version: %{version_id: "v1", is_default_version: true}}} =
               IAM.get_policy_version("arn:aws:iam::123:policy/ReadOnly", "v1",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "list_policies/1" do
    test "returns mocked list" do
      Sandbox.set_list_policies_responses([
        fn -> {:ok, %{policies: [%{policy_name: "ReadOnly"}]}} end
      ])

      assert {:ok, %{policies: [%{policy_name: "ReadOnly"}]}} =
               IAM.list_policies(sandbox: [enabled: true])
    end
  end

  describe "delete_policy/2" do
    test "returns mocked success" do
      Sandbox.set_delete_policy_responses([
        {"arn:aws:iam::123:policy/ReadOnly", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.delete_policy("arn:aws:iam::123:policy/ReadOnly", sandbox: [enabled: true])
    end
  end

  describe "create_policy_version/3" do
    test "returns mocked version" do
      Sandbox.set_create_policy_version_responses([
        {"arn:aws:iam::123:policy/ReadOnly",
         fn -> {:ok, %{policy_version: %{version_id: "v2", is_default_version: true}}} end}
      ])

      assert {:ok, %{policy_version: %{version_id: "v2"}}} =
               IAM.create_policy_version(
                 "arn:aws:iam::123:policy/ReadOnly",
                 %{"Version" => "2012-10-17", "Statement" => []},
                 set_as_default: true,
                 sandbox: [enabled: true]
               )
    end
  end

  describe "set_default_policy_version/3" do
    test "returns mocked success" do
      Sandbox.set_set_default_policy_version_responses([
        {"arn:aws:iam::123:policy/ReadOnly", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.set_default_policy_version(
                 "arn:aws:iam::123:policy/ReadOnly",
                 "v2",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "delete_policy_version/3" do
    test "returns mocked success" do
      Sandbox.set_delete_policy_version_responses([
        {"arn:aws:iam::123:policy/ReadOnly", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.delete_policy_version(
                 "arn:aws:iam::123:policy/ReadOnly",
                 "v1",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "list_policy_versions/2" do
    test "returns mocked versions" do
      Sandbox.set_list_policy_versions_responses([
        {"arn:aws:iam::123:policy/ReadOnly",
         fn ->
           {:ok,
            %{
              versions: [%{version_id: "v1", is_default_version: true}],
              is_truncated: false,
              marker: nil
            }}
         end}
      ])

      assert {:ok, %{versions: [%{version_id: "v1"}], is_truncated: false, marker: nil}} =
               IAM.list_policy_versions("arn:aws:iam::123:policy/ReadOnly",
                 sandbox: [enabled: true]
               )
    end
  end

  # Attachments

  describe "attach_role_policy/3" do
    test "returns mocked success" do
      Sandbox.set_attach_role_policy_responses([
        {"AdminRole", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.attach_role_policy(
                 "AdminRole",
                 "arn:aws:iam::123:policy/ReadOnly",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "detach_role_policy/3" do
    test "returns mocked success" do
      Sandbox.set_detach_role_policy_responses([
        {"AdminRole", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.detach_role_policy(
                 "AdminRole",
                 "arn:aws:iam::123:policy/ReadOnly",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "list_attached_role_policies/2" do
    test "returns mocked list" do
      Sandbox.set_list_attached_role_policies_responses([
        {"AdminRole",
         fn ->
           {:ok,
            %{
              policies: [
                %{policy_name: "ReadOnly", policy_arn: "arn:aws:iam::123:policy/ReadOnly"}
              ]
            }}
         end}
      ])

      assert {:ok, %{policies: [%{policy_name: "ReadOnly"}]}} =
               IAM.list_attached_role_policies("AdminRole", sandbox: [enabled: true])
    end
  end

  describe "attach_user_policy/3" do
    test "returns mocked success" do
      Sandbox.set_attach_user_policy_responses([
        {"alice", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.attach_user_policy("alice", "arn:aws:iam::123:policy/ReadOnly",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "detach_user_policy/3" do
    test "returns mocked success" do
      Sandbox.set_detach_user_policy_responses([
        {"alice", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.detach_user_policy("alice", "arn:aws:iam::123:policy/ReadOnly",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "attach_group_policy/3" do
    test "returns mocked success" do
      Sandbox.set_attach_group_policy_responses([
        {"devs", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.attach_group_policy("devs", "arn:aws:iam::123:policy/ReadOnly",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "detach_group_policy/3" do
    test "returns mocked success" do
      Sandbox.set_detach_group_policy_responses([
        {"devs", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.detach_group_policy("devs", "arn:aws:iam::123:policy/ReadOnly",
                 sandbox: [enabled: true]
               )
    end
  end

  # MFA Devices

  describe "list_mfa_devices/1" do
    test "returns mocked list" do
      Sandbox.set_list_mfa_devices_responses([
        fn ->
          {:ok,
           %{
             mfa_devices: [%{user_name: "alice", serial_number: "arn:aws:iam::123:mfa/alice"}],
             is_truncated: false,
             marker: nil
           }}
        end
      ])

      assert {:ok, %{mfa_devices: [%{user_name: "alice"}]}} =
               IAM.list_mfa_devices(user_name: "alice", sandbox: [enabled: true])
    end
  end

  # Role Policies

  describe "update_assume_role_policy/3" do
    test "returns mocked success" do
      Sandbox.set_update_assume_role_policy_responses([
        {"role-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.update_assume_role_policy(
                 "role-1",
                 %{"Version" => "2012-10-17"},
                 sandbox: [enabled: true]
               )
    end
  end

  describe "put_role_policy/4" do
    test "returns mocked success" do
      Sandbox.set_put_role_policy_responses([
        {"role-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.put_role_policy("role-1", "inline-1", %{"Version" => "2012-10-17"},
                 sandbox: [enabled: true]
               )
    end
  end

  describe "get_role_policy/3" do
    test "returns mocked policy" do
      Sandbox.set_get_role_policy_responses([
        {"role-1",
         fn ->
           {:ok,
            %{role_name: "role-1", policy_name: "inline-1", policy_document: %{"Version" => "x"}}}
         end}
      ])

      assert {:ok, %{role_name: "role-1", policy_name: "inline-1"}} =
               IAM.get_role_policy("role-1", "inline-1", sandbox: [enabled: true])
    end
  end

  describe "delete_role_policy/3" do
    test "returns mocked success" do
      Sandbox.set_delete_role_policy_responses([
        {"role-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} = IAM.delete_role_policy("role-1", "inline-1", sandbox: [enabled: true])
    end
  end

  describe "list_role_policies/2" do
    test "returns mocked list" do
      Sandbox.set_list_role_policies_responses([
        {"role-1",
         fn -> {:ok, %{policy_names: ["inline-1"], is_truncated: false, marker: nil}} end}
      ])

      assert {:ok, %{policy_names: ["inline-1"], is_truncated: false, marker: nil}} =
               IAM.list_role_policies("role-1", sandbox: [enabled: true])
    end
  end

  # OIDC Providers

  describe "create_open_id_connect_provider/2" do
    test "returns mocked success" do
      Sandbox.set_create_open_id_connect_provider_responses([
        {"https://example.com", fn -> {:ok, %{open_id_connect_provider_arn: "arn:oidc-1"}} end}
      ])

      assert {:ok, %{open_id_connect_provider_arn: "arn:oidc-1"}} =
               IAM.create_open_id_connect_provider(
                 "https://example.com",
                 client_id_list: ["sts.amazonaws.com"],
                 thumbprint_list: ["abc"],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "get_open_id_connect_provider/2" do
    test "returns mocked provider" do
      Sandbox.set_get_open_id_connect_provider_responses([
        {"arn:oidc-1",
         fn ->
           {:ok,
            %{
              url: "https://example.com",
              client_id_list: ["sts.amazonaws.com"],
              thumbprint_list: ["abc"],
              create_date: "2026-01-01"
            }}
         end}
      ])

      assert {:ok, %{url: "https://example.com"}} =
               IAM.get_open_id_connect_provider("arn:oidc-1", sandbox: [enabled: true])
    end
  end

  describe "list_open_id_connect_providers/1" do
    test "returns mocked list" do
      Sandbox.set_list_open_id_connect_providers_responses([
        fn -> {:ok, %{open_id_connect_provider_list: [%{arn: "arn:oidc-1"}]}} end
      ])

      assert {:ok, %{open_id_connect_provider_list: [%{arn: "arn:oidc-1"}]}} =
               IAM.list_open_id_connect_providers(sandbox: [enabled: true])
    end
  end

  describe "delete_open_id_connect_provider/2" do
    test "returns mocked success" do
      Sandbox.set_delete_open_id_connect_provider_responses([
        {"arn:oidc-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.delete_open_id_connect_provider("arn:oidc-1", sandbox: [enabled: true])
    end
  end

  describe "update_open_id_connect_provider_thumbprint/3" do
    test "returns mocked success" do
      Sandbox.set_update_open_id_connect_provider_thumbprint_responses([
        {"arn:oidc-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.update_open_id_connect_provider_thumbprint(
                 "arn:oidc-1",
                 ["def"],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "add_client_id_to_open_id_connect_provider/3" do
    test "returns mocked success" do
      Sandbox.set_add_client_id_to_open_id_connect_provider_responses([
        {"arn:oidc-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.add_client_id_to_open_id_connect_provider(
                 "arn:oidc-1",
                 "new-client",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "remove_client_id_from_open_id_connect_provider/3" do
    test "returns mocked success" do
      Sandbox.set_remove_client_id_from_open_id_connect_provider_responses([
        {"arn:oidc-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IAM.remove_client_id_from_open_id_connect_provider(
                 "arn:oidc-1",
                 "old-client",
                 sandbox: [enabled: true]
               )
    end
  end

  # Regex matching

  describe "get_instance_profile/2" do
    test "keys off the profile name" do
      Sandbox.set_get_instance_profile_responses([
        {"web", fn -> {:ok, %{instance_profile: %{instance_profile_name: "web", roles: []}}} end}
      ])

      assert {:ok, %{instance_profile: %{instance_profile_name: "web"}}} =
               IAM.get_instance_profile("web", sandbox: [enabled: true])
    end
  end

  describe "regex matching" do
    test "matches user name by regex" do
      Sandbox.set_create_user_responses([
        {~r/^svc-/, fn -> {:ok, %{user_name: "svc-matched"}} end}
      ])

      assert {:ok, %{user_name: "svc-matched"}} =
               IAM.create_user("svc-deploy", sandbox: [enabled: true])
    end
  end
end
