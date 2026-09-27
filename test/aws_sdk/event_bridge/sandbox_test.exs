defmodule AwsSDK.EventBridge.SandboxTest do
  use ExUnit.Case, async: true

  alias AwsSDK.EventBridge
  alias AwsSDK.EventBridge.Sandbox

  # Rule management

  describe "put_rule/2" do
    test "returns mocked rule ARN" do
      Sandbox.set_put_rule_responses([
        {"my-rule", fn -> {:ok, %{rule_arn: "arn:aws:events:us-west-1:123:rule/my-rule"}} end}
      ])

      assert {:ok, %{rule_arn: "arn:aws:events:us-west-1:123:rule/my-rule"}} =
               EventBridge.put_rule("my-rule", [
                 {:event_pattern, %{"source" => ["aws.s3"]}},
                 {:sandbox, [enabled: true]}
               ])
    end
  end

  describe "describe_rule/2" do
    test "returns mocked rule details" do
      Sandbox.set_describe_rule_responses([
        {"my-rule", fn -> {:ok, %{name: "my-rule", state: "ENABLED"}} end}
      ])

      assert {:ok, %{name: "my-rule", state: "ENABLED"}} =
               EventBridge.describe_rule("my-rule", sandbox: [enabled: true])
    end
  end

  describe "list_rules/1" do
    test "returns mocked rule list" do
      Sandbox.set_list_rules_responses([
        fn -> {:ok, %{rules: [%{name: "my-rule"}], next_token: nil}} end
      ])

      assert {:ok, %{rules: [%{name: "my-rule"}]}} =
               EventBridge.list_rules(sandbox: [enabled: true])
    end
  end

  describe "delete_rule/2" do
    test "returns success" do
      Sandbox.set_delete_rule_responses([
        {"my-rule", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} = EventBridge.delete_rule("my-rule", sandbox: [enabled: true])
    end
  end

  # Target management

  describe "put_targets/3" do
    test "returns mocked target result" do
      Sandbox.set_put_targets_responses([
        {"my-rule", fn -> {:ok, %{failed_entry_count: 0, failed_entries: []}} end}
      ])

      assert {:ok, %{failed_entry_count: 0}} =
               EventBridge.put_targets(
                 "my-rule",
                 [%{id: "1", arn: "arn:aws:sqs:us-west-1:123:q"}],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "list_targets_by_rule/2" do
    test "returns mocked targets" do
      Sandbox.set_list_targets_by_rule_responses([
        {"my-rule", fn -> {:ok, %{targets: [%{id: "1"}], next_token: nil}} end}
      ])

      assert {:ok, %{targets: [%{id: "1"}]}} =
               EventBridge.list_targets_by_rule("my-rule", sandbox: [enabled: true])
    end
  end

  describe "remove_targets/3" do
    test "returns success" do
      Sandbox.set_remove_targets_responses([
        {"my-rule", fn -> {:ok, %{failed_entry_count: 0, failed_entries: []}} end}
      ])

      assert {:ok, %{failed_entry_count: 0}} =
               EventBridge.remove_targets("my-rule", ["1"], sandbox: [enabled: true])
    end
  end

  # Connection management

  describe "create_connection/4" do
    test "returns mocked connection ARN" do
      Sandbox.set_create_connection_responses([
        {"my-conn",
         fn -> {:ok, %{connection_arn: "arn:aws:events:us-west-1:123:connection/my-conn/abc"}} end}
      ])

      assert {:ok, %{connection_arn: "arn:aws:events:us-west-1:123:connection/my-conn/abc"}} =
               EventBridge.create_connection(
                 "my-conn",
                 "API_KEY",
                 %{
                   "ApiKeyAuthParameters" => %{
                     "ApiKeyName" => "x-api-key",
                     "ApiKeyValue" => "secret"
                   }
                 },
                 sandbox: [enabled: true]
               )
    end
  end

  describe "describe_connection/2" do
    test "returns mocked connection details" do
      Sandbox.set_describe_connection_responses([
        {"my-conn", fn -> {:ok, %{name: "my-conn", authorization_type: "API_KEY"}} end}
      ])

      assert {:ok, %{name: "my-conn"}} =
               EventBridge.describe_connection("my-conn", sandbox: [enabled: true])
    end
  end

  describe "update_connection/2" do
    test "returns success" do
      Sandbox.set_update_connection_responses([
        {"my-conn", fn -> {:ok, %{connection_arn: "arn:...", connection_state: "AUTHORIZED"}} end}
      ])

      assert {:ok, _} = EventBridge.update_connection("my-conn", sandbox: [enabled: true])
    end
  end

  describe "delete_connection/2" do
    test "returns success" do
      Sandbox.set_delete_connection_responses([
        {"my-conn", fn -> {:ok, %{connection_arn: "arn:...", connection_state: "DELETING"}} end}
      ])

      assert {:ok, _} = EventBridge.delete_connection("my-conn", sandbox: [enabled: true])
    end
  end

  describe "list_connections/1" do
    test "returns mocked connection list" do
      Sandbox.set_list_connections_responses([
        fn -> {:ok, %{connections: [%{name: "my-conn"}], next_token: nil}} end
      ])

      assert {:ok, %{connections: [%{name: "my-conn"}]}} =
               EventBridge.list_connections(sandbox: [enabled: true])
    end
  end

  # API Destination management

  describe "create_api_destination/5" do
    test "returns mocked API destination ARN" do
      Sandbox.set_create_api_destination_responses([
        {"my-dest",
         fn ->
           {:ok,
            %{
              api_destination_arn: "arn:aws:events:us-west-1:123:api-destination/my-dest/abc",
              api_destination_state: "ACTIVE"
            }}
         end}
      ])

      assert {:ok, %{api_destination_arn: _, api_destination_state: "ACTIVE"}} =
               EventBridge.create_api_destination(
                 "my-dest",
                 "arn:conn",
                 "https://example.com/webhook",
                 "POST",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "describe_api_destination/2" do
    test "returns mocked details" do
      Sandbox.set_describe_api_destination_responses([
        {"my-dest", fn -> {:ok, %{name: "my-dest", http_method: "POST"}} end}
      ])

      assert {:ok, %{name: "my-dest"}} =
               EventBridge.describe_api_destination("my-dest", sandbox: [enabled: true])
    end
  end

  describe "update_api_destination/2" do
    test "returns success" do
      Sandbox.set_update_api_destination_responses([
        {"my-dest", fn -> {:ok, %{api_destination_arn: "arn:..."}} end}
      ])

      assert {:ok, _} = EventBridge.update_api_destination("my-dest", sandbox: [enabled: true])
    end
  end

  describe "delete_api_destination/2" do
    test "returns success" do
      Sandbox.set_delete_api_destination_responses([
        {"my-dest", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} = EventBridge.delete_api_destination("my-dest", sandbox: [enabled: true])
    end
  end

  describe "list_api_destinations/1" do
    test "returns mocked list" do
      Sandbox.set_list_api_destinations_responses([
        fn -> {:ok, %{api_destinations: [%{name: "my-dest"}], next_token: nil}} end
      ])

      assert {:ok, %{api_destinations: [%{name: "my-dest"}]}} =
               EventBridge.list_api_destinations(sandbox: [enabled: true])
    end
  end

  # Event Bus management

  describe "create_event_bus/2" do
    test "returns mocked event bus ARN" do
      Sandbox.set_create_event_bus_responses([
        {"my-bus",
         fn -> {:ok, %{event_bus_arn: "arn:aws:events:us-west-1:123:event-bus/my-bus"}} end}
      ])

      assert {:ok, %{event_bus_arn: _}} =
               EventBridge.create_event_bus("my-bus", sandbox: [enabled: true])
    end
  end

  describe "describe_event_bus/2" do
    test "returns mocked bus details" do
      Sandbox.set_describe_event_bus_responses([
        {"default", fn -> {:ok, %{name: "default", arn: "arn:..."}} end}
      ])

      assert {:ok, %{name: "default"}} =
               EventBridge.describe_event_bus("default", sandbox: [enabled: true])
    end
  end

  describe "delete_event_bus/2" do
    test "returns success" do
      Sandbox.set_delete_event_bus_responses([
        {"my-bus", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} = EventBridge.delete_event_bus("my-bus", sandbox: [enabled: true])
    end
  end

  describe "list_event_buses/1" do
    test "returns mocked bus list" do
      Sandbox.set_list_event_buses_responses([
        fn -> {:ok, %{event_buses: [%{name: "default"}], next_token: nil}} end
      ])

      assert {:ok, %{event_buses: [%{name: "default"}]}} =
               EventBridge.list_event_buses(sandbox: [enabled: true])
    end
  end

  # Event publishing

  describe "put_events/2" do
    test "returns mocked event result" do
      Sandbox.set_put_events_responses([
        fn -> {:ok, %{entries: [%{event_id: "abc-123"}], failed_entry_count: 0}} end
      ])

      assert {:ok, %{failed_entry_count: 0, entries: [%{event_id: "abc-123"}]}} =
               EventBridge.put_events(
                 [%{source: "my-app", detail_type: "Test", detail: "{}"}],
                 sandbox: [enabled: true]
               )
    end
  end

  # Rule control

  describe "enable_rule/2" do
    test "returns success" do
      Sandbox.set_enable_rule_responses([
        {"my-rule", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} = EventBridge.enable_rule("my-rule", sandbox: [enabled: true])
    end
  end

  describe "disable_rule/2" do
    test "returns success" do
      Sandbox.set_disable_rule_responses([
        {"my-rule", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} = EventBridge.disable_rule("my-rule", sandbox: [enabled: true])
    end
  end

  # Pattern helpers (pure functions, no sandbox needed)

  describe "s3_object_created_pattern/1" do
    test "builds correct event pattern" do
      assert %{
               "source" => ["aws.s3"],
               "detail-type" => ["Object Created"],
               "detail" => %{"bucket" => %{"name" => ["my-bucket"]}}
             } = EventBridge.s3_object_created_pattern("my-bucket")
    end
  end

  describe "s3_event_pattern/2" do
    test "builds correct event pattern for any detail type" do
      assert %{
               "source" => ["aws.s3"],
               "detail-type" => ["Object Deleted"],
               "detail" => %{"bucket" => %{"name" => ["my-bucket"]}}
             } = EventBridge.s3_event_pattern("Object Deleted", "my-bucket")
    end
  end

  # Regex matching

  describe "regex matching" do
    test "matches rule name by regex" do
      Sandbox.set_put_rule_responses([
        {~r/^s3-/, fn -> {:ok, %{rule_arn: "arn:matched"}} end}
      ])

      assert {:ok, %{rule_arn: "arn:matched"}} =
               EventBridge.put_rule("s3-uploads", sandbox: [enabled: true])
    end
  end
end
