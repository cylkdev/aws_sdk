defmodule AwsSDK.SSM.SandboxTest do
  use ExUnit.Case, async: true

  alias AwsSDK.SSM
  alias AwsSDK.SSM.Sandbox

  describe "get_parameter/2" do
    test "returns the parameter registered for the name" do
      Sandbox.set_get_parameter_responses([
        {"/app/db/host",
         fn ->
           {:ok, %{parameter: %{name: "/app/db/host", type: "String", value: "db.internal"}}}
         end}
      ])

      assert {:ok, %{parameter: %{name: "/app/db/host", type: "String", value: "db.internal"}}} =
               SSM.get_parameter("/app/db/host", sandbox: [enabled: true])
    end

    test "matches the parameter name by regex" do
      Sandbox.set_get_parameter_responses([
        {~r|^/app/|, fn -> {:ok, %{parameter: %{value: "matched"}}} end}
      ])

      assert {:ok, %{parameter: %{value: "matched"}}} =
               SSM.get_parameter("/app/anything", sandbox: [enabled: true])
    end
  end

  describe "get_parameters/2" do
    test "returns the parameters registered for the names" do
      Sandbox.set_get_parameters_responses([
        fn -> {:ok, %{parameters: [%{name: "/a"}, %{name: "/b"}], invalid_parameters: []}} end
      ])

      assert {:ok, %{parameters: [%{name: "/a"}, %{name: "/b"}], invalid_parameters: []}} =
               SSM.get_parameters(["/a", "/b"], sandbox: [enabled: true])
    end
  end

  describe "get_parameters_by_path/2" do
    test "returns the parameters registered under the path" do
      Sandbox.set_get_parameters_by_path_responses([
        {"/app/", fn -> {:ok, %{parameters: [%{name: "/app/db/host"}], next_token: nil}} end}
      ])

      assert {:ok, %{parameters: [%{name: "/app/db/host"}], next_token: nil}} =
               SSM.get_parameters_by_path("/app/", sandbox: [enabled: true])
    end
  end

  describe "put_parameter/3" do
    test "returns the version registered for the name" do
      Sandbox.set_put_parameter_responses([
        {"/app/feature_flag", fn -> {:ok, %{version: 1, tier: "Standard"}} end}
      ])

      assert {:ok, %{version: 1, tier: "Standard"}} =
               SSM.put_parameter("/app/feature_flag", "on", sandbox: [enabled: true])
    end
  end

  describe "delete_parameter/2" do
    test "returns the response registered for the name" do
      Sandbox.set_delete_parameter_responses([{"/app/db/host", fn -> {:ok, %{}} end}])

      assert {:ok, %{}} = SSM.delete_parameter("/app/db/host", sandbox: [enabled: true])
    end
  end

  describe "delete_parameters/2" do
    test "returns the deleted and invalid names" do
      Sandbox.set_delete_parameters_responses([
        fn -> {:ok, %{deleted_parameters: ["/a", "/b"], invalid_parameters: []}} end
      ])

      assert {:ok, %{deleted_parameters: ["/a", "/b"], invalid_parameters: []}} =
               SSM.delete_parameters(["/a", "/b"], sandbox: [enabled: true])
    end
  end

  describe "describe_parameters/1" do
    test "returns the registered parameter metadata" do
      Sandbox.set_describe_parameters_responses([
        fn -> {:ok, %{parameters: [%{name: "/app/db/host", type: "String"}], next_token: nil}} end
      ])

      assert {:ok, %{parameters: [%{name: "/app/db/host", type: "String"}], next_token: nil}} =
               SSM.describe_parameters(sandbox: [enabled: true])
    end
  end

  describe "describe_instance_information/1" do
    test "returns the registered managed node information" do
      Sandbox.set_describe_instance_information_responses([
        fn ->
          {:ok,
           %{
             instance_information_list: [
               %{instance_id: "i-1234567890abcdef0", ping_status: "Online"}
             ],
             next_token: nil
           }}
        end
      ])

      assert {:ok,
              %{
                instance_information_list: [
                  %{instance_id: "i-1234567890abcdef0", ping_status: "Online"}
                ],
                next_token: nil
              }} = SSM.describe_instance_information(sandbox: [enabled: true])
    end
  end

  describe "send_command/3" do
    test "returns the registered command" do
      Sandbox.set_send_command_responses([
        fn ->
          {:ok,
           %{
             command: %{
               command_id: "cmd-123",
               document_name: "AWS-RunShellScript",
               instance_ids: ["i-1"],
               status: "Pending"
             }
           }}
        end
      ])

      assert {:ok, %{command: %{command_id: "cmd-123"}}} =
               SSM.send_command(["i-1"], "AWS-RunShellScript",
                 parameters: %{"commands" => ["uptime"]},
                 sandbox: [enabled: true]
               )
    end
  end

  describe "send_command_by_targets/3" do
    test "returns the registered command" do
      Sandbox.set_send_command_by_targets_responses([
        fn -> {:ok, %{command: %{command_id: "cmd-456", status: "Pending"}}} end
      ])

      assert {:ok, %{command: %{command_id: "cmd-456"}}} =
               SSM.send_command_by_targets(
                 [%{key: "tag:Role", values: ["web"]}],
                 "AWS-RunShellScript",
                 sandbox: [enabled: true]
               )
    end
  end

  describe "get_command_invocation/3" do
    test "keys off the command id" do
      Sandbox.set_get_command_invocation_responses([
        {"cmd-123",
         fn ->
           {:ok,
            %{
              command_id: "cmd-123",
              instance_id: "i-1",
              status: "Success",
              status_details: "Success",
              response_code: 0,
              standard_output_content: "ok\n",
              standard_error_content: ""
            }}
         end}
      ])

      assert {:ok, %{status: "Success", standard_output_content: "ok\n"}} =
               SSM.get_command_invocation("cmd-123", "i-1", sandbox: [enabled: true])
    end
  end

  describe "list_command_invocations/1" do
    test "returns the registered invocations" do
      Sandbox.set_list_command_invocations_responses([
        fn ->
          {:ok,
           %{
             command_invocations: [
               %{command_id: "cmd-123", instance_id: "i-1", status: "Success"},
               %{command_id: "cmd-123", instance_id: "i-2", status: "InProgress"}
             ],
             next_token: nil
           }}
        end
      ])

      assert {:ok, %{command_invocations: [_, _]}} =
               SSM.list_command_invocations(command_id: "cmd-123", sandbox: [enabled: true])
    end
  end
end
