defmodule AwsSDK.AutoScaling.SandboxTest do
  use ExUnit.Case, async: true

  alias AwsSDK.AutoScaling
  alias AwsSDK.AutoScaling.Sandbox

  describe "describe_auto_scaling_groups/1" do
    test "returns the registered groups" do
      Sandbox.set_describe_auto_scaling_groups_responses([
        fn ->
          {:ok,
           %{
             auto_scaling_groups: [%{auto_scaling_group_name: "my-asg", instances: []}],
             next_token: nil
           }}
        end
      ])

      assert {:ok,
              %{auto_scaling_groups: [%{auto_scaling_group_name: "my-asg"}], next_token: nil}} =
               AutoScaling.describe_auto_scaling_groups(sandbox: [enabled: true])
    end

    test "returns the response registered for the slot a tag:Slot filter names" do
      Sandbox.set_describe_auto_scaling_groups_responses([
        {"blue",
         fn ->
           {:ok,
            %{auto_scaling_groups: [%{auto_scaling_group_name: "blue-asg"}], next_token: nil}}
         end},
        {"green",
         fn ->
           {:ok,
            %{auto_scaling_groups: [%{auto_scaling_group_name: "green-asg"}], next_token: nil}}
         end},
        fn ->
          {:ok,
           %{
             auto_scaling_groups: [
               %{auto_scaling_group_name: "blue-asg"},
               %{auto_scaling_group_name: "green-asg"}
             ],
             next_token: nil
           }}
        end
      ])

      assert {:ok, %{auto_scaling_groups: [%{auto_scaling_group_name: "green-asg"}]}} =
               AutoScaling.describe_auto_scaling_groups(
                 filters: [
                   %{name: "tag:ReleaseApp", values: ["cylk-web"]},
                   %{name: "tag:Slot", values: ["green"]}
                 ],
                 sandbox: [enabled: true]
               )
    end

    test "falls back to the stub for every call when no tag:Slot filter names a slot" do
      Sandbox.set_describe_auto_scaling_groups_responses([
        {"blue",
         fn ->
           {:ok,
            %{auto_scaling_groups: [%{auto_scaling_group_name: "blue-asg"}], next_token: nil}}
         end},
        fn ->
          {:ok,
           %{
             auto_scaling_groups: [
               %{auto_scaling_group_name: "blue-asg"},
               %{auto_scaling_group_name: "green-asg"}
             ],
             next_token: nil
           }}
        end
      ])

      assert {:ok,
              %{
                auto_scaling_groups: [
                  %{auto_scaling_group_name: "blue-asg"},
                  %{auto_scaling_group_name: "green-asg"}
                ]
              }} =
               AutoScaling.describe_auto_scaling_groups(
                 filters: [%{name: "tag:ReleaseApp", values: ["cylk-web"]}],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "describe_instance_refreshes/2" do
    test "returns the refreshes registered for the group" do
      Sandbox.set_describe_instance_refreshes_responses([
        {"my-asg",
         fn ->
           {:ok,
            %{
              instance_refreshes: [%{instance_refresh_id: "r-1", status: "InProgress"}],
              next_token: nil
            }}
         end}
      ])

      assert {:ok, %{instance_refreshes: [%{instance_refresh_id: "r-1", status: "InProgress"}]}} =
               AutoScaling.describe_instance_refreshes("my-asg", sandbox: [enabled: true])
    end
  end

  describe "complete_lifecycle_action/4" do
    test "returns the response registered for the hook and group" do
      Sandbox.set_complete_lifecycle_action_responses([
        {"my-hook|my-asg", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               AutoScaling.complete_lifecycle_action(
                 "my-hook",
                 "my-asg",
                 "CONTINUE",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "record_lifecycle_action_heartbeat/3" do
    test "returns the response registered for the hook and group" do
      Sandbox.set_record_lifecycle_action_heartbeat_responses([
        {"my-hook|my-asg", fn -> {:ok, %{}} end}
      ])

      assert {:ok, %{}} =
               AutoScaling.record_lifecycle_action_heartbeat(
                 "my-hook",
                 "my-asg",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "set_instance_health/3" do
    test "returns the response registered for the instance" do
      Sandbox.set_set_instance_health_responses([{"i-aaaa", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} =
               AutoScaling.set_instance_health("i-aaaa", "Unhealthy", sandbox: [enabled: true])
    end
  end

  describe "set_desired_capacity/3" do
    test "returns the response registered for the group" do
      Sandbox.set_set_desired_capacity_responses([{"my-asg", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} = AutoScaling.set_desired_capacity("my-asg", 5, sandbox: [enabled: true])
    end
  end

  describe "describe_scaling_activities/2" do
    test "keys off the group name" do
      Sandbox.set_describe_scaling_activities_responses([
        {"web-asg",
         fn ->
           {:ok,
            %{
              activities: [%{activity_id: "act-1", status_code: "InProgress"}],
              next_token: nil
            }}
         end}
      ])

      assert {:ok, %{activities: [%{status_code: "InProgress"}]}} =
               AutoScaling.describe_scaling_activities("web-asg",
                 max_records: 10,
                 sandbox: [enabled: true]
               )
    end
  end
end
