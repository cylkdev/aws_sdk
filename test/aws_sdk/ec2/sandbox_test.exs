defmodule AwsSDK.EC2.SandboxTest do
  use ExUnit.Case, async: true

  alias AwsSDK.EC2
  alias AwsSDK.EC2.Sandbox

  describe "create_security_group/4" do
    test "returns the response registered for the group name" do
      Sandbox.set_create_security_group_responses([{"web", fn -> {:ok, %{group_id: "sg-1"}} end}])

      assert {:ok, %{group_id: "sg-1"}} =
               EC2.create_security_group("web", "web tier", "vpc-1", sandbox: [enabled: true])
    end

    test "matches the group name by regex" do
      Sandbox.set_create_security_group_responses([
        {~r/^web-/, fn -> {:ok, %{group_id: "sg-matched"}} end}
      ])

      assert {:ok, %{group_id: "sg-matched"}} =
               EC2.create_security_group("web-prod", "desc", "vpc-1", sandbox: [enabled: true])
    end
  end

  describe "describe_security_groups/1" do
    test "returns the registered groups" do
      Sandbox.set_describe_security_groups_responses([
        fn -> {:ok, %{security_group_info: [%{group_id: "sg-1", group_name: "web"}]}} end
      ])

      assert {:ok, %{security_group_info: [%{group_id: "sg-1", group_name: "web"}]}} =
               EC2.describe_security_groups(sandbox: [enabled: true])
    end
  end

  describe "delete_security_group/1" do
    test "returns the registered response" do
      Sandbox.set_delete_security_group_responses([fn -> {:ok, %{}} end])

      assert {:ok, %{}} = EC2.delete_security_group(group_id: "sg-1", sandbox: [enabled: true])
    end
  end

  describe "authorize_security_group_ingress/3" do
    test "returns the response registered for the group id" do
      Sandbox.set_authorize_security_group_ingress_responses([{"sg-1", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} =
               EC2.authorize_security_group_ingress(
                 "sg-1",
                 [%{protocol: "tcp", from_port: 443, to_port: 443}],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "revoke_security_group_ingress/3" do
    test "returns the response registered for the group id" do
      Sandbox.set_revoke_security_group_ingress_responses([{"sg-1", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} =
               EC2.revoke_security_group_ingress(
                 "sg-1",
                 [%{protocol: "tcp", from_port: 443, to_port: 443}],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "authorize_security_group_egress/3" do
    test "returns the response registered for the group id" do
      Sandbox.set_authorize_security_group_egress_responses([{"sg-1", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} =
               EC2.authorize_security_group_egress(
                 "sg-1",
                 [%{protocol: "tcp", from_port: 443, to_port: 443}],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "revoke_security_group_egress/3" do
    test "returns the response registered for the group id" do
      Sandbox.set_revoke_security_group_egress_responses([{"sg-1", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} =
               EC2.revoke_security_group_egress(
                 "sg-1",
                 [%{protocol: "tcp", from_port: 443, to_port: 443}],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "describe_vpcs/1" do
    test "returns the registered vpcs" do
      Sandbox.set_describe_vpcs_responses([
        fn ->
          {:ok, %{vpc_set: [%{vpc_id: "vpc-1", cidr_block: "10.0.0.0/16", is_default: true}]}}
        end
      ])

      assert {:ok, %{vpc_set: [%{vpc_id: "vpc-1", cidr_block: "10.0.0.0/16", is_default: true}]}} =
               EC2.describe_vpcs(sandbox: [enabled: true])
    end
  end

  describe "describe_subnets/1" do
    test "returns the registered subnets" do
      Sandbox.set_describe_subnets_responses([
        fn -> {:ok, %{subnet_set: [%{subnet_id: "subnet-1", vpc_id: "vpc-1"}]}} end
      ])

      assert {:ok, %{subnet_set: [%{subnet_id: "subnet-1", vpc_id: "vpc-1"}]}} =
               EC2.describe_subnets(sandbox: [enabled: true])
    end
  end

  describe "describe_instances/1" do
    test "returns the registered reservations" do
      Sandbox.set_describe_instances_responses([
        fn -> {:ok, %{reservation_set: [%{instances_set: [%{instance_id: "i-1"}]}]}} end
      ])

      assert {:ok, %{reservation_set: [%{instances_set: [%{instance_id: "i-1"}]}]}} =
               EC2.describe_instances(sandbox: [enabled: true])
    end
  end

  describe "create_tags/3" do
    test "returns the response registered for the first resource id" do
      Sandbox.set_create_tags_responses([{"i-1", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} =
               EC2.create_tags(["i-1"], [%{key: "Name", value: "web-1"}],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "describe_tags/1" do
    test "returns the registered tags" do
      Sandbox.set_describe_tags_responses([
        fn -> {:ok, %{tag_set: [%{key: "Name", value: "web-1", resource_id: "i-1"}]}} end
      ])

      assert {:ok, %{tag_set: [%{key: "Name", value: "web-1", resource_id: "i-1"}]}} =
               EC2.describe_tags(sandbox: [enabled: true])
    end
  end

  describe "describe_images/1" do
    test "returns the registered images" do
      Sandbox.set_describe_images_responses([
        fn ->
          {:ok,
           %{
             images_set: [
               %{
                 image_id: "ami-111",
                 block_device_mapping: [
                   %{device_name: "/dev/xvda", ebs: %{snapshot_id: "snap-aaa"}}
                 ]
               }
             ]
           }}
        end
      ])

      assert {:ok,
              %{
                images_set: [
                  %{
                    image_id: "ami-111",
                    block_device_mapping: [
                      %{device_name: "/dev/xvda", ebs: %{snapshot_id: "snap-aaa"}}
                    ]
                  }
                ]
              }} = EC2.describe_images(sandbox: [enabled: true])
    end
  end

  describe "deregister_image/2" do
    test "returns the response registered for the image id" do
      Sandbox.set_deregister_image_responses([{"ami-111", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} = EC2.deregister_image("ami-111", sandbox: [enabled: true])
    end
  end

  describe "delete_snapshot/2" do
    test "returns the response registered for the snapshot id" do
      Sandbox.set_delete_snapshot_responses([{"snap-aaa", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} = EC2.delete_snapshot("snap-aaa", sandbox: [enabled: true])
    end
  end

  describe "describe_launch_templates/1" do
    test "returns the registered launch templates" do
      Sandbox.set_describe_launch_templates_responses([
        fn ->
          {:ok,
           %{
             launch_templates: [
               %{
                 launch_template_id: "lt-1",
                 launch_template_name: "web",
                 default_version_number: 1,
                 latest_version_number: 3
               }
             ],
             next_token: nil
           }}
        end
      ])

      assert {:ok, %{launch_templates: [%{launch_template_id: "lt-1"}]}} =
               EC2.describe_launch_templates(sandbox: [enabled: true])
    end
  end

  describe "describe_launch_template_versions/1" do
    test "returns the registered versions with their template data" do
      Sandbox.set_describe_launch_template_versions_responses([
        fn ->
          {:ok,
           %{
             launch_template_versions: [
               %{
                 launch_template_id: "lt-1",
                 version_number: 3,
                 launch_template_data: %{
                   image_id: "ami-1",
                   instance_type: "t3.micro",
                   placement: %{group_name: "g"}
                 }
               }
             ],
             next_token: nil
           }}
        end
      ])

      assert {:ok,
              %{
                launch_template_versions: [
                  %{version_number: 3, launch_template_data: %{image_id: "ami-1"}}
                ]
              }} =
               EC2.describe_launch_template_versions(
                 launch_template_id: "lt-1",
                 sandbox: [enabled: true]
               )
    end

    test "returns the response registered for the launch template id" do
      Sandbox.set_describe_launch_template_versions_responses([
        {"lt-1", fn -> {:ok, %{launch_template_versions: [%{version_number: 1}], next_token: nil}} end},
        {"lt-2", fn -> {:ok, %{launch_template_versions: [%{version_number: 2}], next_token: nil}} end}
      ])

      assert {:ok, %{launch_template_versions: [%{version_number: 2}]}} =
               EC2.describe_launch_template_versions(
                 launch_template_id: "lt-2",
                 sandbox: [enabled: true]
               )
    end

    test "falls back to a stub registered for every call when the id is not named" do
      Sandbox.set_describe_launch_template_versions_responses([
        fn -> {:ok, %{launch_template_versions: [%{version_number: 9}], next_token: nil}} end
      ])

      assert {:ok, %{launch_template_versions: [%{version_number: 9}]}} =
               EC2.describe_launch_template_versions(
                 launch_template_id: nil,
                 versions: ["$Default"],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "create_launch_template_version/3" do
    test "returns the response registered for the launch template id" do
      Sandbox.set_create_launch_template_version_responses([
        {"lt-1",
         fn ->
           {:ok,
            %{
              launch_template_version: %{
                launch_template_id: "lt-1",
                version_number: 2,
                default_version: "false"
              },
              warning: nil
            }}
         end}
      ])

      assert {:ok,
              %{
                launch_template_version: %{
                  launch_template_id: "lt-1",
                  version_number: 2,
                  default_version: "false"
                },
                warning: nil
              }} =
               EC2.create_launch_template_version("lt-1", %{"ImageId" => "ami-1"},
                 sandbox: [enabled: true]
               )
    end

    test "matches the launch template id by regex" do
      Sandbox.set_create_launch_template_version_responses([
        {~r/^lt-/,
         fn -> {:ok, %{launch_template_version: %{version_number: 7}, warning: nil}} end}
      ])

      assert {:ok, %{launch_template_version: %{version_number: 7}, warning: nil}} =
               EC2.create_launch_template_version("lt-matched", %{"ImageId" => "ami-1"},
                 sandbox: [enabled: true]
               )
    end

    test "passes the launch template id to a function that takes it" do
      Sandbox.set_create_launch_template_version_responses([
        {"lt-1",
         fn launch_template_id ->
           {:ok,
            %{launch_template_version: %{launch_template_id: launch_template_id}, warning: nil}}
         end}
      ])

      assert {:ok, %{launch_template_version: %{launch_template_id: "lt-1"}, warning: nil}} =
               EC2.create_launch_template_version("lt-1", %{"ImageId" => "ami-1"},
                 sandbox: [enabled: true]
               )
    end
  end

  describe "modify_launch_template/3" do
    test "returns the response registered for the launch template id" do
      Sandbox.set_modify_launch_template_responses([
        {"lt-1",
         fn ->
           {:ok,
            %{
              launch_template: %{
                launch_template_id: "lt-1",
                default_version_number: 3,
                latest_version_number: 7
              }
            }}
         end}
      ])

      assert {:ok,
              %{
                launch_template: %{
                  launch_template_id: "lt-1",
                  default_version_number: 3,
                  latest_version_number: 7
                }
              }} = EC2.modify_launch_template("lt-1", "3", sandbox: [enabled: true])
    end

    test "matches the launch template id by regex" do
      Sandbox.set_modify_launch_template_responses([
        {~r/^lt-/, fn -> {:ok, %{launch_template: %{default_version_number: 9}}} end}
      ])

      assert {:ok, %{launch_template: %{default_version_number: 9}}} =
               EC2.modify_launch_template("lt-matched", "9", sandbox: [enabled: true])
    end

    test "passes the launch template id to a function that takes it" do
      Sandbox.set_modify_launch_template_responses([
        {"lt-1",
         fn launch_template_id ->
           {:ok, %{launch_template: %{launch_template_id: launch_template_id}}}
         end}
      ])

      assert {:ok, %{launch_template: %{launch_template_id: "lt-1"}}} =
               EC2.modify_launch_template("lt-1", "3", sandbox: [enabled: true])
    end
  end

  describe "terminate_instances/2" do
    test "returns the registered state changes" do
      Sandbox.set_terminate_instances_responses([
        fn ->
          {:ok,
           %{
             instances_set: [
               %{
                 instance_id: "i-1",
                 current_state: %{code: 32, name: "shutting-down"},
                 previous_state: %{code: 16, name: "running"}
               }
             ]
           }}
        end
      ])

      assert {:ok, %{instances_set: [%{instance_id: "i-1"}]}} =
               EC2.terminate_instances(["i-1"], sandbox: [enabled: true])
    end
  end

  describe "get_console_output/2" do
    test "keys off the instance id" do
      Sandbox.set_get_console_output_responses([
        {"i-1", fn -> {:ok, %{instance_id: "i-1", timestamp: nil, output: "boot ok\n"}} end}
      ])

      assert {:ok, %{output: "boot ok\n"}} =
               EC2.get_console_output("i-1", sandbox: [enabled: true])
    end
  end

  describe "describe_network_acls/1" do
    test "returns the registered ACLs" do
      Sandbox.set_describe_network_acls_responses([
        fn -> {:ok, %{network_acl_set: [%{network_acl_id: "acl-1"}], next_token: nil}} end
      ])

      assert {:ok, %{network_acl_set: [%{network_acl_id: "acl-1"}]}} =
               EC2.describe_network_acls(sandbox: [enabled: true])
    end
  end

  describe "describe_route_tables/1" do
    test "returns the registered route tables" do
      Sandbox.set_describe_route_tables_responses([
        fn -> {:ok, %{route_table_set: [%{route_table_id: "rtb-1"}], next_token: nil}} end
      ])

      assert {:ok, %{route_table_set: [%{route_table_id: "rtb-1"}]}} =
               EC2.describe_route_tables(sandbox: [enabled: true])
    end
  end

  describe "describe_key_pairs/1" do
    test "returns the registered key pairs" do
      Sandbox.set_describe_key_pairs_responses([
        fn -> {:ok, %{key_set: [%{key_name: "deploy"}]}} end
      ])

      assert {:ok, %{key_set: [%{key_name: "deploy"}]}} =
               EC2.describe_key_pairs(sandbox: [enabled: true])
    end
  end

  describe "delete_key_pair/2" do
    test "keys off the key name" do
      Sandbox.set_delete_key_pair_responses([
        {"deploy", fn -> {:ok, %{return: true, key_pair_id: "key-1"}} end}
      ])

      assert {:ok, %{return: true}} = EC2.delete_key_pair("deploy", sandbox: [enabled: true])
    end
  end

  describe "describe_security_group_rules/1" do
    test "returns the registered rules" do
      Sandbox.set_describe_security_group_rules_responses([
        fn ->
          {:ok, %{security_group_rule_set: [%{security_group_rule_id: "sgr-1"}], next_token: nil}}
        end
      ])

      assert {:ok, %{security_group_rule_set: [%{security_group_rule_id: "sgr-1"}]}} =
               EC2.describe_security_group_rules(sandbox: [enabled: true])
    end
  end

  describe "describe_snapshots/1" do
    test "returns the registered snapshots" do
      Sandbox.set_describe_snapshots_responses([
        fn -> {:ok, %{snapshot_set: [%{snapshot_id: "snap-1"}], next_token: nil}} end
      ])

      assert {:ok, %{snapshot_set: [%{snapshot_id: "snap-1"}]}} =
               EC2.describe_snapshots(owner_ids: ["self"], sandbox: [enabled: true])
    end
  end

  describe "describe_network_interfaces/1" do
    test "returns the registered interfaces" do
      Sandbox.set_describe_network_interfaces_responses([
        fn ->
          {:ok, %{network_interface_set: [%{network_interface_id: "eni-1"}], next_token: nil}}
        end
      ])

      assert {:ok, %{network_interface_set: [%{network_interface_id: "eni-1"}]}} =
               EC2.describe_network_interfaces(sandbox: [enabled: true])
    end
  end

  describe "describe_instance_status/1" do
    test "returns the registered statuses" do
      Sandbox.set_describe_instance_status_responses([
        fn ->
          {:ok, %{instance_status_set: [%{instance_id: "i-1"}], next_token: nil}}
        end
      ])

      assert {:ok, %{instance_status_set: [%{instance_id: "i-1"}]}} =
               EC2.describe_instance_status(
                 instance_ids: ["i-1"],
                 include_all_instances: true,
                 sandbox: [enabled: true]
               )
    end
  end

  describe "describe_iam_instance_profile_associations/1" do
    test "returns the registered associations" do
      Sandbox.set_describe_iam_instance_profile_associations_responses([
        fn ->
          {:ok,
           %{
             iam_instance_profile_association_set: [%{association_id: "iip-assoc-1"}],
             next_token: nil
           }}
        end
      ])

      assert {:ok, %{iam_instance_profile_association_set: [%{association_id: "iip-assoc-1"}]}} =
               EC2.describe_iam_instance_profile_associations(sandbox: [enabled: true])
    end
  end

  describe "create_network_insights_path/4" do
    test "keys off the source" do
      Sandbox.set_create_network_insights_path_responses([
        {"i-1", fn -> {:ok, %{network_insights_path: %{network_insights_path_id: "nip-1"}}} end}
      ])

      assert {:ok, %{network_insights_path: %{network_insights_path_id: "nip-1"}}} =
               EC2.create_network_insights_path("i-1", "i-2", "tcp",
                 destination_port: 443,
                 sandbox: [enabled: true]
               )
    end
  end

  describe "start_network_insights_analysis/2" do
    test "keys off the path id" do
      Sandbox.set_start_network_insights_analysis_responses([
        {"nip-1",
         fn ->
           {:ok,
            %{
              network_insights_analysis: %{
                network_insights_analysis_id: "nia-1",
                status: "running"
              }
            }}
         end}
      ])

      assert {:ok, %{network_insights_analysis: %{status: "running"}}} =
               EC2.start_network_insights_analysis("nip-1", sandbox: [enabled: true])
    end
  end

  describe "describe_network_insights_analyses/1" do
    test "returns the registered analyses" do
      Sandbox.set_describe_network_insights_analyses_responses([
        fn ->
          {:ok,
           %{
             network_insights_analysis_set: [%{status: "succeeded", network_path_found: true}],
             next_token: nil
           }}
        end
      ])

      assert {:ok, %{network_insights_analysis_set: [%{network_path_found: true}]}} =
               EC2.describe_network_insights_analyses(
                 analysis_ids: ["nia-1"],
                 sandbox: [enabled: true]
               )
    end
  end

  describe "delete_network_insights_path/2" do
    test "keys off the path id" do
      Sandbox.set_delete_network_insights_path_responses([
        {"nip-1", fn -> {:ok, %{network_insights_path_id: "nip-1"}} end}
      ])

      assert {:ok, %{network_insights_path_id: "nip-1"}} =
               EC2.delete_network_insights_path("nip-1", sandbox: [enabled: true])
    end
  end
end
