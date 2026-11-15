defmodule AwsSDK.ElasticLoadBalancingV2.SandboxTest do
  use ExUnit.Case, async: true

  alias AwsSDK.ElasticLoadBalancingV2
  alias AwsSDK.ElasticLoadBalancingV2.Sandbox

  describe "describe_target_groups/1" do
    test "returns the registered target groups" do
      Sandbox.set_describe_target_groups_responses([
        fn ->
          {:ok,
           %{
             target_groups: [%{target_group_arn: "arn:tg/a", target_group_name: "a"}],
             next_marker: nil
           }}
        end
      ])

      assert {:ok,
              %{
                target_groups: [%{target_group_arn: "arn:tg/a", target_group_name: "a"}],
                next_marker: nil
              }} = ElasticLoadBalancingV2.describe_target_groups(sandbox: [enabled: true])
    end
  end

  describe "describe_target_groups_by_names/2" do
    test "returns the response registered for the joined names" do
      Sandbox.set_describe_target_groups_by_names_responses([
        {"a,b", fn -> {:ok, %{target_groups: [], next_marker: nil}} end}
      ])

      assert {:ok, %{target_groups: [], next_marker: nil}} =
               ElasticLoadBalancingV2.describe_target_groups_by_names(["a", "b"],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "describe_target_groups_by_arns/2" do
    test "returns the response registered for the joined arns" do
      Sandbox.set_describe_target_groups_by_arns_responses([
        {"arn:tg/a", fn -> {:ok, %{target_groups: [], next_marker: nil}} end}
      ])

      assert {:ok, %{target_groups: [], next_marker: nil}} =
               ElasticLoadBalancingV2.describe_target_groups_by_arns(["arn:tg/a"],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "describe_target_groups_by_load_balancer/2" do
    test "returns the response registered for the load balancer arn" do
      Sandbox.set_describe_target_groups_by_load_balancer_responses([
        {"arn:lb/x", fn -> {:ok, %{target_groups: [], next_marker: nil}} end}
      ])

      assert {:ok, %{target_groups: [], next_marker: nil}} =
               ElasticLoadBalancingV2.describe_target_groups_by_load_balancer("arn:lb/x",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "describe_target_health/2" do
    test "returns the response registered for the target group arn" do
      Sandbox.set_describe_target_health_responses([
        {"arn:tg/mine",
         fn ->
           {:ok,
            %{target_health_descriptions: [%{target_id: "i-0abc", port: 4000, state: "healthy"}]}}
         end}
      ])

      assert {:ok,
              %{
                target_health_descriptions: [%{target_id: "i-0abc", port: 4000, state: "healthy"}]
              }} =
               ElasticLoadBalancingV2.describe_target_health("arn:tg/mine",
                 sandbox: [enabled: true]
               )
    end

    test "matches the target group arn by regex" do
      Sandbox.set_describe_target_health_responses([
        {~r|targetgroup/web|, fn -> {:ok, %{target_health_descriptions: []}} end}
      ])

      assert {:ok, %{target_health_descriptions: []}} =
               ElasticLoadBalancingV2.describe_target_health("arn:targetgroup/web-dev",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "describe_load_balancers/1" do
    test "returns the registered load balancers" do
      Sandbox.set_describe_load_balancers_responses([
        fn ->
          {:ok,
           %{
             load_balancers: [
               %{load_balancer_arn: "arn:lb/deployd-dev", load_balancer_name: "deployd-dev"}
             ],
             next_marker: nil
           }}
        end
      ])

      assert {:ok,
              %{
                load_balancers: [
                  %{load_balancer_arn: "arn:lb/deployd-dev", load_balancer_name: "deployd-dev"}
                ],
                next_marker: nil
              }} = ElasticLoadBalancingV2.describe_load_balancers(sandbox: [enabled: true])
    end
  end

  describe "describe_listeners/2" do
    test "returns the response registered for the load balancer arn" do
      Sandbox.set_describe_listeners_responses([
        {"arn:lb/x",
         fn ->
           {:ok, %{listeners: [%{listener_arn: "arn:listener/80", port: 80}], next_marker: nil}}
         end}
      ])

      assert {:ok, %{listeners: [%{listener_arn: "arn:listener/80", port: 80}], next_marker: nil}} =
               ElasticLoadBalancingV2.describe_listeners("arn:lb/x", sandbox: [enabled: true])
    end

    test "rejects a load balancer arn that is not a binary" do
      assert_raise FunctionClauseError, fn ->
        ElasticLoadBalancingV2.describe_listeners(nil, sandbox: [enabled: true])
      end
    end
  end

  describe "describe_listeners_by_arns/2" do
    test "returns the response registered for the joined listener arns" do
      Sandbox.set_describe_listeners_by_arns_responses([
        {"arn:listener/80,arn:listener/443", fn -> {:ok, %{listeners: [], next_marker: nil}} end}
      ])

      assert {:ok, %{listeners: [], next_marker: nil}} =
               ElasticLoadBalancingV2.describe_listeners_by_arns(
                 ["arn:listener/80", "arn:listener/443"],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "describe_rules/2" do
    test "returns the response registered for the listener arn" do
      Sandbox.set_describe_rules_responses([
        {"arn:listener/80",
         fn ->
           {:ok,
            %{
              rules: [
                %{
                  rule_arn: "arn:rule/1",
                  conditions: [%{field: "host-header"}],
                  actions: [%{type: "forward"}]
                }
              ],
              next_marker: nil
            }}
         end}
      ])

      assert {:ok,
              %{
                rules: [
                  %{
                    rule_arn: "arn:rule/1",
                    conditions: [%{field: "host-header"}],
                    actions: [%{type: "forward"}]
                  }
                ],
                next_marker: nil
              }} =
               ElasticLoadBalancingV2.describe_rules("arn:listener/80", sandbox: [enabled: true])
    end

    test "rejects a listener arn that is not a binary" do
      assert_raise FunctionClauseError, fn ->
        ElasticLoadBalancingV2.describe_rules(nil, sandbox: [enabled: true])
      end
    end
  end

  describe "describe_rules_by_arns/2" do
    test "returns the response registered for the joined rule arns" do
      Sandbox.set_describe_rules_by_arns_responses([
        {"arn:rule/1,arn:rule/2", fn -> {:ok, %{rules: [], next_marker: nil}} end}
      ])

      assert {:ok, %{rules: [], next_marker: nil}} =
               ElasticLoadBalancingV2.describe_rules_by_arns(["arn:rule/1", "arn:rule/2"],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "modify_rule/3" do
    test "returns the response registered for the rule arn" do
      Sandbox.set_modify_rule_responses([
        {"arn:rule/1", fn -> {:ok, %{rules: [%{rule_arn: "arn:rule/1"}]}} end}
      ])

      assert {:ok, %{rules: [%{rule_arn: "arn:rule/1"}]}} =
               ElasticLoadBalancingV2.modify_rule(
                 "arn:rule/1",
                 [%{"Type" => "forward"}],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "modify_listener/3" do
    test "keys off the listener arn" do
      Sandbox.set_modify_listener_responses([
        {"arn:listener/1",
         fn -> {:ok, %{listeners: [%{listener_arn: "arn:listener/1", port: 443}]}} end}
      ])

      assert {:ok, %{listeners: [%{listener_arn: "arn:listener/1"}]}} =
               ElasticLoadBalancingV2.modify_listener(
                 "arn:listener/1",
                 [%{type: "fixed-response", fixed_response_config: %{status_code: "503"}}],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "create_load_balancer/2" do
    test "keys off the load balancer name" do
      Sandbox.set_create_load_balancer_responses([
        {"web", fn -> {:ok, %{load_balancers: [%{load_balancer_name: "web"}]}} end}
      ])

      assert {:ok, %{load_balancers: [%{load_balancer_name: "web"}]}} ===
               ElasticLoadBalancingV2.create_load_balancer("web", sandbox: [enabled: true])
    end
  end

  describe "create_target_group/2" do
    test "keys off the target group name" do
      Sandbox.set_create_target_group_responses([
        {"web", fn -> {:ok, %{target_groups: [%{target_group_name: "web"}]}} end}
      ])

      assert {:ok, %{target_groups: [%{target_group_name: "web"}]}} ===
               ElasticLoadBalancingV2.create_target_group("web", sandbox: [enabled: true])
    end
  end

  describe "create_listener/3" do
    test "keys off the load balancer arn" do
      Sandbox.set_create_listener_responses([
        {"arn:lb/1", fn -> {:ok, %{listeners: [%{load_balancer_arn: "arn:lb/1"}]}} end}
      ])

      assert {:ok, %{listeners: [%{load_balancer_arn: "arn:lb/1"}]}} ===
               ElasticLoadBalancingV2.create_listener(
                 "arn:lb/1",
                 [%{"Type" => "forward", "TargetGroupArn" => "arn:tg/1"}],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "create_rule/5" do
    test "keys off the listener arn" do
      Sandbox.set_create_rule_responses([
        {"arn:listener/1", fn -> {:ok, %{rules: [%{priority: "10"}]}} end}
      ])

      assert {:ok, %{rules: [%{priority: "10"}]}} ===
               ElasticLoadBalancingV2.create_rule(
                 "arn:listener/1",
                 [%{"Field" => "path-pattern", "Values" => ["/api/*"]}],
                 10,
                 [%{"Type" => "forward", "TargetGroupArn" => "arn:tg/1"}],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "register_targets/3" do
    test "keys off the target group arn" do
      Sandbox.set_register_targets_responses([{"arn:tg/1", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} ===
               ElasticLoadBalancingV2.register_targets(
                 "arn:tg/1",
                 [%{"Id" => "10.0.1.10", "Port" => 80}],
                 sandbox: [enabled: true]
               )
    end
  end
end
