if Code.ensure_loaded?(SandboxRegistry) do
  defmodule AwsSDK.EC2.Sandbox do
    @moduledoc false

    @registry :aws_ec2_sandbox

    alias AwsSDK.Sandbox

    def start_link, do: Sandbox.start_link(@registry)

    @spec disable_aws_ec2_sandbox(map) :: :ok
    def disable_aws_ec2_sandbox(_context), do: Sandbox.disable(@registry, __MODULE__)

    @spec sandbox_disabled? :: boolean
    def sandbox_disabled?, do: Sandbox.disabled?(@registry, __MODULE__)

    def create_security_group_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_security_group, name, binding)
    end

    def set_create_security_group_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_security_group, entries)
    end

    def describe_security_groups_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_security_groups, :*, binding)
    end

    def set_describe_security_groups_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_security_groups, entries)
    end

    def delete_security_group_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_security_group, :*, binding)
    end

    def set_delete_security_group_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_security_group, entries)
    end

    def authorize_security_group_ingress_response(group_id, opts) do
      binding = [group_id: group_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :authorize_security_group_ingress, group_id, binding)
    end

    def set_authorize_security_group_ingress_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :authorize_security_group_ingress, entries)
    end

    def revoke_security_group_ingress_response(group_id, opts) do
      binding = [group_id: group_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :revoke_security_group_ingress, group_id, binding)
    end

    def set_revoke_security_group_ingress_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :revoke_security_group_ingress, entries)
    end

    def authorize_security_group_egress_response(group_id, opts) do
      binding = [group_id: group_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :authorize_security_group_egress, group_id, binding)
    end

    def set_authorize_security_group_egress_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :authorize_security_group_egress, entries)
    end

    def revoke_security_group_egress_response(group_id, opts) do
      binding = [group_id: group_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :revoke_security_group_egress, group_id, binding)
    end

    def set_revoke_security_group_egress_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :revoke_security_group_egress, entries)
    end

    def describe_vpcs_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_vpcs, :*, binding)
    end

    def set_describe_vpcs_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_vpcs, entries)
    end

    def describe_subnets_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_subnets, :*, binding)
    end

    def set_describe_subnets_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_subnets, entries)
    end

    def describe_instances_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_instances, :*, binding)
    end

    def set_describe_instances_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_instances, entries)
    end

    def describe_images_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_images, :*, binding)
    end

    def set_describe_images_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_images, entries)
    end

    def deregister_image_response(image_id, opts) do
      binding = [image_id: image_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :deregister_image, image_id, binding)
    end

    def set_deregister_image_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :deregister_image, entries)
    end

    def delete_snapshot_response(snapshot_id, opts) do
      binding = [snapshot_id: snapshot_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_snapshot, snapshot_id, binding)
    end

    def set_delete_snapshot_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_snapshot, entries)
    end

    def create_tags_response(resource_ids, opts) do
      binding = [resource_ids: resource_ids, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_tags, Enum.join(resource_ids, ","), binding)
    end

    def set_create_tags_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_tags, entries)
    end

    def describe_tags_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_tags, :*, binding)
    end

    def set_describe_tags_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_tags, entries)
    end

    def describe_launch_templates_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_launch_templates, :*, binding)
    end

    def set_describe_launch_templates_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_launch_templates, entries)
    end

    def describe_launch_template_versions_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :describe_launch_template_versions,
        opts[:launch_template_id] || :*,
        binding
      )
    end

    def set_describe_launch_template_versions_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_launch_template_versions, entries)
    end

    def create_launch_template_version_response(launch_template_id, opts) do
      binding = [launch_template_id: launch_template_id, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :create_launch_template_version,
        launch_template_id,
        binding
      )
    end

    def set_create_launch_template_version_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_launch_template_version, entries)
    end

    def modify_launch_template_response(launch_template_id, opts) do
      binding = [launch_template_id: launch_template_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :modify_launch_template, launch_template_id, binding)
    end

    def set_modify_launch_template_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :modify_launch_template, entries)
    end

    def delete_launch_template_version_response(launch_template_id, opts) do
      binding = [launch_template_id: launch_template_id, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :delete_launch_template_version,
        launch_template_id,
        binding
      )
    end

    def set_delete_launch_template_version_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_launch_template_version, entries)
    end

    def terminate_instances_response(instance_ids, opts) do
      binding = [instance_ids: instance_ids, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :terminate_instances, :*, binding)
    end

    def set_terminate_instances_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :terminate_instances, entries)
    end

    def get_console_output_response(instance_id, opts) do
      binding = [instance_id: instance_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_console_output, instance_id, binding)
    end

    def set_get_console_output_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_console_output, entries)
    end

    def describe_network_acls_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_network_acls, :*, binding)
    end

    def set_describe_network_acls_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_network_acls, entries)
    end

    def describe_route_tables_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_route_tables, :*, binding)
    end

    def set_describe_route_tables_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_route_tables, entries)
    end

    def describe_key_pairs_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_key_pairs, :*, binding)
    end

    def set_describe_key_pairs_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_key_pairs, entries)
    end

    def delete_key_pair_response(key_name, opts) do
      binding = [key_name: key_name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_key_pair, key_name, binding)
    end

    def set_delete_key_pair_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_key_pair, entries)
    end

    def describe_security_group_rules_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_security_group_rules, :*, binding)
    end

    def set_describe_security_group_rules_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_security_group_rules, entries)
    end

    def describe_snapshots_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_snapshots, :*, binding)
    end

    def set_describe_snapshots_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_snapshots, entries)
    end

    def describe_network_interfaces_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_network_interfaces, :*, binding)
    end

    def set_describe_network_interfaces_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_network_interfaces, entries)
    end

    def describe_instance_status_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_instance_status, :*, binding)
    end

    def set_describe_instance_status_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_instance_status, entries)
    end

    def describe_iam_instance_profile_associations_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :describe_iam_instance_profile_associations,
        :*,
        binding
      )
    end

    def set_describe_iam_instance_profile_associations_responses(entries) do
      Sandbox.register(
        @registry,
        __MODULE__,
        :describe_iam_instance_profile_associations,
        entries
      )
    end

    def create_network_insights_path_response(source, destination, protocol, opts) do
      binding = [source: source, destination: destination, protocol: protocol, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_network_insights_path, source, binding)
    end

    def set_create_network_insights_path_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_network_insights_path, entries)
    end

    def start_network_insights_analysis_response(path_id, opts) do
      binding = [path_id: path_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :start_network_insights_analysis, path_id, binding)
    end

    def set_start_network_insights_analysis_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :start_network_insights_analysis, entries)
    end

    def describe_network_insights_analyses_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_network_insights_analyses, :*, binding)
    end

    def set_describe_network_insights_analyses_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_network_insights_analyses, entries)
    end

    def delete_network_insights_path_response(path_id, opts) do
      binding = [path_id: path_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_network_insights_path, path_id, binding)
    end

    def set_delete_network_insights_path_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_network_insights_path, entries)
    end
  end
end
