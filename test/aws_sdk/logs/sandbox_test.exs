defmodule AwsSDK.Logs.SandboxTest do
  use ExUnit.Case, async: true

  alias AwsSDK.Logs
  alias AwsSDK.Logs.Sandbox

  describe "create_log_group/2" do
    test "returns the response registered for the group" do
      Sandbox.set_create_log_group_responses([{"my-group", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} = Logs.create_log_group("my-group", sandbox: [enabled: true])
    end

    test "matches the group name by regex" do
      Sandbox.set_create_log_group_responses([{~r/^app-/, fn -> {:ok, %{matched: true}} end}])

      assert {:ok, %{matched: true}} = Logs.create_log_group("app-prod", sandbox: [enabled: true])
    end
  end

  describe "delete_log_group/2" do
    test "returns the response registered for the group" do
      Sandbox.set_delete_log_group_responses([{"my-group", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} = Logs.delete_log_group("my-group", sandbox: [enabled: true])
    end
  end

  describe "describe_log_groups/1" do
    test "returns the registered groups" do
      Sandbox.set_describe_log_groups_responses([
        fn -> {:ok, %{log_groups: [%{log_group_name: "my-group"}], next_token: nil}} end
      ])

      assert {:ok, %{log_groups: [%{log_group_name: "my-group"}], next_token: nil}} =
               Logs.describe_log_groups(sandbox: [enabled: true])
    end
  end

  describe "put_retention_policy/3" do
    test "returns the response registered for the group" do
      Sandbox.set_put_retention_policy_responses([{"my-group", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} = Logs.put_retention_policy("my-group", 30, sandbox: [enabled: true])
    end
  end

  describe "delete_retention_policy/2" do
    test "returns the response registered for the group" do
      Sandbox.set_delete_retention_policy_responses([{"my-group", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} = Logs.delete_retention_policy("my-group", sandbox: [enabled: true])
    end
  end

  describe "create_log_stream/3" do
    test "returns the response registered for the group" do
      Sandbox.set_create_log_stream_responses([{"my-group", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} =
               Logs.create_log_stream("my-group", "my-stream", sandbox: [enabled: true])
    end
  end

  describe "delete_log_stream/3" do
    test "returns the response registered for the group" do
      Sandbox.set_delete_log_stream_responses([{"my-group", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} =
               Logs.delete_log_stream("my-group", "my-stream", sandbox: [enabled: true])
    end
  end

  describe "describe_log_streams/2" do
    test "returns the registered streams" do
      Sandbox.set_describe_log_streams_responses([
        {"my-group", fn -> {:ok, %{log_streams: [%{log_stream_name: "s1"}], next_token: nil}} end}
      ])

      assert {:ok, %{log_streams: [%{log_stream_name: "s1"}], next_token: nil}} =
               Logs.describe_log_streams("my-group", sandbox: [enabled: true])
    end
  end

  describe "put_log_events/4" do
    test "returns the response registered for the group" do
      Sandbox.set_put_log_events_responses([
        {"my-group", fn -> {:ok, %{next_sequence_token: "t-1"}} end}
      ])

      assert {:ok, %{next_sequence_token: "t-1"}} =
               Logs.put_log_events(
                 "my-group",
                 "my-stream",
                 [%{timestamp: 1_700_000_000_000, message: "hello"}],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "get_log_events/3" do
    test "returns the registered events" do
      Sandbox.set_get_log_events_responses([
        {"my-group",
         fn ->
           {:ok,
            %{
              events: [%{timestamp: 1, message: "m", ingestion_time: 2}],
              next_forward_token: "t"
            }}
         end}
      ])

      assert {:ok,
              %{
                events: [%{timestamp: 1, message: "m", ingestion_time: 2}],
                next_forward_token: "t"
              }} = Logs.get_log_events("my-group", "my-stream", sandbox: [enabled: true])
    end
  end

  describe "filter_log_events/2" do
    test "returns the registered events" do
      Sandbox.set_filter_log_events_responses([
        {"my-group", fn -> {:ok, %{events: [%{message: "boom"}], next_token: nil}} end}
      ])

      assert {:ok, %{events: [%{message: "boom"}], next_token: nil}} =
               Logs.filter_log_events("my-group", sandbox: [enabled: true])
    end
  end

  describe "start_query/5" do
    test "returns the query id registered for the group" do
      Sandbox.set_start_query_responses([{"my-group", fn -> {:ok, %{query_id: "q-1"}} end}])

      assert {:ok, %{query_id: "q-1"}} =
               Logs.start_query("my-group", 1, 2, "fields @message", sandbox: [enabled: true])
    end
  end

  describe "start_query_for_log_groups/5" do
    test "returns the query id registered for the joined group names" do
      Sandbox.set_start_query_for_log_groups_responses([
        {"g1,g2", fn -> {:ok, %{query_id: "q-2"}} end}
      ])

      assert {:ok, %{query_id: "q-2"}} =
               Logs.start_query_for_log_groups(
                 ["g1", "g2"],
                 1,
                 2,
                 "fields @message",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "start_query_by_identifiers/5" do
    test "returns the query id registered for the joined identifiers" do
      Sandbox.set_start_query_by_identifiers_responses([
        {"arn:aws:logs:::g", fn -> {:ok, %{query_id: "q-3"}} end}
      ])

      assert {:ok, %{query_id: "q-3"}} =
               Logs.start_query_by_identifiers(
                 ["arn:aws:logs:::g"],
                 1,
                 2,
                 "fields @message",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "get_query_results/2" do
    test "returns the results registered for the query" do
      Sandbox.set_get_query_results_responses([
        {"q-1", fn -> {:ok, %{status: "Complete", results: []}} end}
      ])

      assert {:ok, %{status: "Complete", results: []}} =
               Logs.get_query_results("q-1", sandbox: [enabled: true])
    end
  end

  describe "stop_query/2" do
    test "returns the response registered for the query" do
      Sandbox.set_stop_query_responses([{"q-1", fn -> {:ok, %{success: true}} end}])

      assert {:ok, %{success: true}} = Logs.stop_query("q-1", sandbox: [enabled: true])
    end
  end
end
