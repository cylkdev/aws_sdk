defmodule AwsSDK.Organizations.SandboxTest do
  use ExUnit.Case, async: true

  alias AwsSDK.Organizations
  alias AwsSDK.Organizations.Sandbox

  # Organization

  describe "create_organization/1" do
    test "returns mocked success" do
      Sandbox.set_create_organization_responses([
        fn -> {:ok, %{organization: %{id: "o-1", feature_set: "ALL"}}} end
      ])

      assert {:ok, %{organization: %{id: "o-1", feature_set: "ALL"}}} =
               Organizations.create_organization(sandbox: [enabled: true])
    end
  end

  describe "delete_organization/1" do
    test "returns mocked success" do
      Sandbox.set_delete_organization_responses([
        fn -> {:ok, %{}} end
      ])

      assert {:ok, %{}} = Organizations.delete_organization(sandbox: [enabled: true])
    end
  end

  describe "describe_organization/1" do
    test "returns mocked success" do
      Sandbox.set_describe_organization_responses([
        fn -> {:ok, %{organization: %{id: "o-1", feature_set: "ALL"}}} end
      ])

      assert {:ok, %{organization: %{id: "o-1"}}} =
               Organizations.describe_organization(sandbox: [enabled: true])
    end
  end

  # Organizational Units

  describe "create_organizational_unit/3" do
    test "returns mocked success" do
      Sandbox.set_create_organizational_unit_responses([
        {"Workloads", fn -> {:ok, %{organizational_unit: %{id: "ou-1", name: "Workloads"}}} end}
      ])

      assert {:ok, %{organizational_unit: %{id: "ou-1"}}} =
               Organizations.create_organizational_unit("r-abcd", "Workloads",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "delete_organizational_unit/2" do
    test "returns mocked success" do
      Sandbox.set_delete_organizational_unit_responses([
        {"ou-1", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               Organizations.delete_organizational_unit("ou-1", sandbox: [enabled: true])
    end
  end

  describe "list_organizational_units_for_parent/2" do
    test "returns mocked list" do
      Sandbox.set_list_organizational_units_for_parent_responses([
        {"r-abcd", fn -> {:ok, %{organizational_units: [%{id: "ou-1", name: "Workloads"}]}} end}
      ])

      assert {:ok, %{organizational_units: [%{id: "ou-1"}]}} =
               Organizations.list_organizational_units_for_parent("r-abcd",
                 sandbox: [enabled: true]
               )
    end
  end

  # Accounts

  describe "create_account/3" do
    test "returns mocked success" do
      Sandbox.set_create_account_responses([
        {"tools", fn -> {:ok, %{create_account_status: %{id: "car-1", state: "IN_PROGRESS"}}} end}
      ])

      assert {:ok, %{create_account_status: %{id: "car-1"}}} =
               Organizations.create_account("tools", "tools@example.com",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "describe_create_account_status/2" do
    test "returns mocked success" do
      Sandbox.set_describe_create_account_status_responses([
        {"car-1",
         fn ->
           {:ok,
            %{
              create_account_status: %{
                id: "car-1",
                state: "SUCCEEDED",
                account_id: "111122223333"
              }
            }}
         end}
      ])

      assert {:ok, %{create_account_status: %{state: "SUCCEEDED"}}} =
               Organizations.describe_create_account_status("car-1", sandbox: [enabled: true])
    end
  end

  describe "move_account/4" do
    test "returns mocked success" do
      Sandbox.set_move_account_responses([
        {"111122223333", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               Organizations.move_account("111122223333", "r-abcd", "ou-1",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "close_account/2" do
    test "returns mocked success" do
      Sandbox.set_close_account_responses([
        {"111122223333", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} = Organizations.close_account("111122223333", sandbox: [enabled: true])
    end
  end

  describe "list_accounts/1" do
    test "returns mocked list" do
      Sandbox.set_list_accounts_responses([
        fn -> {:ok, %{accounts: [%{id: "111122223333", name: "tools"}], next_token: nil}} end
      ])

      assert {:ok, %{accounts: [%{id: "111122223333"}], next_token: nil}} =
               Organizations.list_accounts(sandbox: [enabled: true])
    end
  end

  # Roots

  describe "list_roots/1" do
    test "returns mocked list" do
      Sandbox.set_list_roots_responses([
        fn -> {:ok, %{roots: [%{id: "r-abcd", name: "Root"}]}} end
      ])

      assert {:ok, %{roots: [%{id: "r-abcd"}]}} =
               Organizations.list_roots(sandbox: [enabled: true])
    end
  end

  describe "get_root/1" do
    test "returns the first root from list_roots" do
      Sandbox.set_list_roots_responses([
        fn -> {:ok, %{roots: [%{id: "r-abcd", name: "Root"}, %{id: "r-other"}]}} end
      ])

      assert {:ok, %{id: "r-abcd"}} = Organizations.get_root(sandbox: [enabled: true])
    end
  end

  # Delegated administrators / service access

  describe "register_delegated_administrator/3" do
    test "returns mocked success" do
      Sandbox.set_register_delegated_administrator_responses([
        {"111122223333", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               Organizations.register_delegated_administrator(
                 "111122223333",
                 "billing.amazonaws.com",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "enable_aws_service_access/2" do
    test "returns mocked success" do
      Sandbox.set_enable_aws_service_access_responses([
        {"sso.amazonaws.com", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               Organizations.enable_aws_service_access("sso.amazonaws.com",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "list_delegated_administrators/1" do
    test "returns mocked list" do
      Sandbox.set_list_delegated_administrators_responses([
        fn -> {:ok, %{delegated_administrators: [%{id: "111122223333"}]}} end
      ])

      assert {:ok, %{delegated_administrators: [%{id: "111122223333"}]}} =
               Organizations.list_delegated_administrators(sandbox: [enabled: true])
    end
  end

  describe "describe_account/2" do
    test "returns mocked account" do
      Sandbox.set_describe_account_responses([
        {"111122223333", fn -> {:ok, %{account: %{id: "111122223333", name: "tools"}}} end}
      ])

      assert {:ok, %{account: %{id: "111122223333", name: "tools"}}} =
               Organizations.describe_account("111122223333", sandbox: [enabled: true])
    end
  end

  describe "describe_organizational_unit/2" do
    test "returns mocked OU" do
      Sandbox.set_describe_organizational_unit_responses([
        {"ou-1", fn -> {:ok, %{organizational_unit: %{id: "ou-1", name: "Workloads"}}} end}
      ])

      assert {:ok, %{organizational_unit: %{id: "ou-1"}}} =
               Organizations.describe_organizational_unit("ou-1", sandbox: [enabled: true])
    end
  end

  describe "update_organizational_unit/3" do
    test "returns mocked OU" do
      Sandbox.set_update_organizational_unit_responses([
        {"ou-1", fn -> {:ok, %{organizational_unit: %{id: "ou-1", name: "Workloads2"}}} end}
      ])

      assert {:ok, %{organizational_unit: %{name: "Workloads2"}}} =
               Organizations.update_organizational_unit("ou-1", "Workloads2",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "disable_aws_service_access/2" do
    test "returns mocked success" do
      Sandbox.set_disable_aws_service_access_responses([
        {"sso.amazonaws.com", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               Organizations.disable_aws_service_access("sso.amazonaws.com",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "deregister_delegated_administrator/3" do
    test "returns mocked success" do
      Sandbox.set_deregister_delegated_administrator_responses([
        {"111122223333", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               Organizations.deregister_delegated_administrator(
                 "111122223333",
                 "billing.amazonaws.com",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "list_children/3" do
    test "returns mocked children" do
      Sandbox.set_list_children_responses([
        {"ou-1",
         fn -> {:ok, %{children: [%{id: "111122223333", type: "ACCOUNT"}], next_token: nil}} end}
      ])

      assert {:ok, %{children: [%{id: "111122223333", type: "ACCOUNT"}], next_token: nil}} =
               Organizations.list_children("ou-1", "ACCOUNT", sandbox: [enabled: true])
    end
  end

  # Regex matching

  describe "regex matching" do
    test "matches OU name by regex" do
      Sandbox.set_create_organizational_unit_responses([
        {~r/^Workloads-/, fn -> {:ok, %{organizational_unit: %{matched: true}}} end}
      ])

      assert {:ok, %{organizational_unit: %{matched: true}}} =
               Organizations.create_organizational_unit("r-abcd", "Workloads-prod",
                 sandbox: [enabled: true]
               )
    end
  end
end
