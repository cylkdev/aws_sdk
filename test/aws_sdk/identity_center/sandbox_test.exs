defmodule AwsSDK.IdentityCenter.SandboxTest do
  use ExUnit.Case, async: true

  alias AwsSDK.IdentityCenter
  alias AwsSDK.IdentityCenter.Sandbox

  # Instances

  describe "list_instances/1" do
    test "returns mocked list" do
      Sandbox.set_list_instances_responses([
        fn -> {:ok, %{instances: [%{instance_arn: "arn:aws:sso:::instance/ssoins-1"}]}} end
      ])

      assert {:ok, %{instances: [%{instance_arn: "arn:aws:sso:::instance/ssoins-1"}]}} =
               IdentityCenter.list_instances(sandbox: [enabled: true])
    end
  end

  # Permission Sets

  describe "create_permission_set/3" do
    test "returns mocked success" do
      Sandbox.set_create_permission_set_responses([
        {"admin", fn -> {:ok, %{permission_set_arn: "ps-1"}} end}
      ])

      assert {:ok, %{permission_set_arn: "ps-1"}} =
               IdentityCenter.create_permission_set("arn:ins", "admin", sandbox: [enabled: true])
    end
  end

  describe "delete_permission_set/3" do
    test "returns mocked success" do
      Sandbox.set_delete_permission_set_responses([
        {"ps-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IdentityCenter.delete_permission_set("arn:ins", "ps-1", sandbox: [enabled: true])
    end
  end

  describe "list_permission_sets/2" do
    test "returns mocked list" do
      Sandbox.set_list_permission_sets_responses([
        {"arn:ins", fn -> {:ok, %{permission_sets: ["ps-1", "ps-2"], next_token: nil}} end}
      ])

      assert {:ok, %{permission_sets: ["ps-1", "ps-2"]}} =
               IdentityCenter.list_permission_sets("arn:ins", sandbox: [enabled: true])
    end
  end

  describe "attach_managed_policy_to_permission_set/4" do
    test "returns mocked success" do
      Sandbox.set_attach_managed_policy_to_permission_set_responses([
        {"ps-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IdentityCenter.attach_managed_policy_to_permission_set(
                 "arn:ins",
                 "ps-1",
                 "arn:aws:iam::aws:policy/ReadOnlyAccess",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "detach_managed_policy_from_permission_set/4" do
    test "returns mocked success" do
      Sandbox.set_detach_managed_policy_from_permission_set_responses([
        {"ps-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IdentityCenter.detach_managed_policy_from_permission_set(
                 "arn:ins",
                 "ps-1",
                 "arn:aws:iam::aws:policy/ReadOnlyAccess",
                 sandbox: [enabled: true]
               )
    end
  end

  # Account Assignments

  describe "create_account_assignment/3" do
    test "returns mocked success" do
      Sandbox.set_create_account_assignment_responses([
        {"arn:ins", fn -> {:ok, %{status: "IN_PROGRESS"}} end}
      ])

      assignment = %{
        target_id: "111122223333",
        target_type: "AWS_ACCOUNT",
        permission_set_arn: "ps-1",
        principal_type: "USER",
        principal_id: "u-1"
      }

      assert {:ok, %{status: "IN_PROGRESS"}} =
               IdentityCenter.create_account_assignment("arn:ins", assignment,
                 sandbox: [enabled: true]
               )
    end
  end

  describe "delete_account_assignment/3" do
    test "returns mocked success" do
      Sandbox.set_delete_account_assignment_responses([
        {"arn:ins", fn -> {:ok, %{status: "IN_PROGRESS"}} end}
      ])

      assignment = %{
        target_id: "111122223333",
        target_type: "AWS_ACCOUNT",
        permission_set_arn: "ps-1",
        principal_type: "USER",
        principal_id: "u-1"
      }

      assert {:ok, %{status: "IN_PROGRESS"}} =
               IdentityCenter.delete_account_assignment("arn:ins", assignment,
                 sandbox: [enabled: true]
               )
    end
  end

  describe "provision_permission_set/3" do
    test "returns mocked status" do
      Sandbox.set_provision_permission_set_responses([
        {"ps-1", fn -> {:ok, %{status: "IN_PROGRESS", request_id: "r-1"}} end}
      ])

      assert {:ok, %{status: "IN_PROGRESS"}} =
               IdentityCenter.provision_permission_set("arn:ins", "ps-1",
                 sandbox: [enabled: true]
               )
    end
  end

  # Identity Store — Users

  describe "create_identity_store_user/3" do
    test "returns mocked success" do
      Sandbox.set_create_identity_store_user_responses([
        {"alice", fn -> {:ok, %{user_id: "u-1"}} end}
      ])

      assert {:ok, %{user_id: "u-1"}} =
               IdentityCenter.create_identity_store_user("d-123", "alice",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "delete_identity_store_user/3" do
    test "returns mocked success" do
      Sandbox.set_delete_identity_store_user_responses([
        {"u-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IdentityCenter.delete_identity_store_user("d-123", "u-1", sandbox: [enabled: true])
    end
  end

  describe "update_identity_store_user/3" do
    test "returns mocked success" do
      Sandbox.set_update_identity_store_user_responses([
        {"u-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IdentityCenter.update_identity_store_user(
                 "d-123",
                 "u-1",
                 display_name: "Alice A.",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "list_identity_store_users/2" do
    test "returns mocked list with next_token" do
      Sandbox.set_list_identity_store_users_responses([
        {"d-123", fn -> {:ok, %{users: [%{user_name: "alice"}], next_token: "t-1"}} end}
      ])

      assert {:ok, %{users: [%{user_name: "alice"}], next_token: "t-1"}} =
               IdentityCenter.list_identity_store_users("d-123", sandbox: [enabled: true])
    end
  end

  describe "describe_identity_store_user/3" do
    test "returns mocked user" do
      Sandbox.set_describe_identity_store_user_responses([
        {"u-1", fn -> {:ok, %{user_id: "u-1", user_name: "alice"}} end}
      ])

      assert {:ok, %{user_id: "u-1", user_name: "alice"}} =
               IdentityCenter.describe_identity_store_user("d-123", "u-1",
                 sandbox: [enabled: true]
               )
    end
  end

  # Identity Store — Groups

  describe "create_identity_store_group/3" do
    test "returns mocked success" do
      Sandbox.set_create_identity_store_group_responses([
        {"engineers", fn -> {:ok, %{group_id: "g-1"}} end}
      ])

      assert {:ok, %{group_id: "g-1"}} =
               IdentityCenter.create_identity_store_group("d-123", "engineers",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "delete_identity_store_group/3" do
    test "returns mocked success" do
      Sandbox.set_delete_identity_store_group_responses([
        {"g-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IdentityCenter.delete_identity_store_group("d-123", "g-1",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "list_identity_store_groups/2" do
    test "returns mocked list with next_token" do
      Sandbox.set_list_identity_store_groups_responses([
        {"d-123", fn -> {:ok, %{groups: [%{display_name: "engineers"}], next_token: nil}} end}
      ])

      assert {:ok, %{groups: [%{display_name: "engineers"}], next_token: nil}} =
               IdentityCenter.list_identity_store_groups("d-123", sandbox: [enabled: true])
    end
  end

  describe "describe_identity_store_group/3" do
    test "returns mocked group" do
      Sandbox.set_describe_identity_store_group_responses([
        {"g-1", fn -> {:ok, %{group_id: "g-1", display_name: "engineers"}} end}
      ])

      assert {:ok, %{group_id: "g-1", display_name: "engineers"}} =
               IdentityCenter.describe_identity_store_group("d-123", "g-1",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "create_group_membership/4" do
    test "returns mocked success" do
      Sandbox.set_create_group_membership_responses([
        {"g-1", fn -> {:ok, %{membership_id: "m-1"}} end}
      ])

      assert {:ok, %{membership_id: "m-1"}} =
               IdentityCenter.create_group_membership("d-123", "g-1", "u-1",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "delete_group_membership/3" do
    test "returns mocked success" do
      Sandbox.set_delete_group_membership_responses([
        {"m-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               IdentityCenter.delete_group_membership("d-123", "m-1", sandbox: [enabled: true])
    end
  end

  # Regex matching

  describe "regex matching" do
    test "matches permission set name by regex" do
      Sandbox.set_create_permission_set_responses([
        {~r/^admin-/, fn -> {:ok, %{matched: true}} end}
      ])

      assert {:ok, %{matched: true}} =
               IdentityCenter.create_permission_set("arn:ins", "admin-prod",
                 sandbox: [enabled: true]
               )
    end
  end
end
