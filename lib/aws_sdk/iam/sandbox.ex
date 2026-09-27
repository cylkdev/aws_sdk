if Code.ensure_loaded?(SandboxRegistry) do
  defmodule AwsSDK.IAM.Sandbox do
    @moduledoc false

    @registry :aws_iam_sandbox

    alias AwsSDK.Sandbox

    def start_link, do: Sandbox.start_link(@registry)

    @spec disable_aws_iam_sandbox(map) :: :ok
    def disable_aws_iam_sandbox(_context), do: Sandbox.disable(@registry, __MODULE__)

    @spec sandbox_disabled? :: boolean
    def sandbox_disabled?, do: Sandbox.disabled?(@registry, __MODULE__)

    def create_user_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_user, name, binding)
    end

    def set_create_user_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_user, entries)
    end

    def get_user_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_user, :*, binding)
    end

    def set_get_user_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_user, entries)
    end

    def list_users_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_users, :*, binding)
    end

    def set_list_users_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_users, entries)
    end

    def delete_user_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_user, name, binding)
    end

    def set_delete_user_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_user, entries)
    end

    def create_access_key_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_access_key, :*, binding)
    end

    def set_create_access_key_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_access_key, entries)
    end

    def list_access_keys_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_access_keys, :*, binding)
    end

    def set_list_access_keys_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_access_keys, entries)
    end

    def delete_access_key_response(key_id, opts) do
      binding = [key_id: key_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_access_key, key_id, binding)
    end

    def set_delete_access_key_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_access_key, entries)
    end

    def create_group_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_group, name, binding)
    end

    def set_create_group_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_group, entries)
    end

    def list_groups_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_groups, :*, binding)
    end

    def set_list_groups_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_groups, entries)
    end

    def delete_group_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_group, name, binding)
    end

    def set_delete_group_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_group, entries)
    end

    def add_user_to_group_response(group, user, opts) do
      binding = [group: group, user: user, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :add_user_to_group, group, binding)
    end

    def set_add_user_to_group_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :add_user_to_group, entries)
    end

    def remove_user_from_group_response(group, user, opts) do
      binding = [group: group, user: user, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :remove_user_from_group, group, binding)
    end

    def set_remove_user_from_group_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :remove_user_from_group, entries)
    end

    def create_role_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_role, name, binding)
    end

    def set_create_role_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_role, entries)
    end

    def get_role_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_role, name, binding)
    end

    def set_get_role_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_role, entries)
    end

    def get_instance_profile_response(instance_profile_name, opts) do
      binding = [instance_profile_name: instance_profile_name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_instance_profile, instance_profile_name, binding)
    end

    def set_get_instance_profile_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_instance_profile, entries)
    end

    def list_roles_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_roles, :*, binding)
    end

    def set_list_roles_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_roles, entries)
    end

    def delete_role_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_role, name, binding)
    end

    def set_delete_role_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_role, entries)
    end

    def create_policy_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_policy, name, binding)
    end

    def set_create_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_policy, entries)
    end

    def get_policy_response(arn, opts) do
      binding = [arn: arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_policy, arn, binding)
    end

    def set_get_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_policy, entries)
    end

    def get_policy_version_response(arn, version_id, opts) do
      binding = [arn: arn, version_id: version_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_policy_version, arn, binding)
    end

    def set_get_policy_version_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_policy_version, entries)
    end

    def create_policy_version_response(arn, opts) do
      binding = [arn: arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_policy_version, arn, binding)
    end

    def set_create_policy_version_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_policy_version, entries)
    end

    def set_default_policy_version_response(arn, version_id, opts) do
      binding = [arn: arn, version_id: version_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :set_default_policy_version, arn, binding)
    end

    def set_set_default_policy_version_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :set_default_policy_version, entries)
    end

    def delete_policy_version_response(arn, version_id, opts) do
      binding = [arn: arn, version_id: version_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_policy_version, arn, binding)
    end

    def set_delete_policy_version_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_policy_version, entries)
    end

    def list_policy_versions_response(arn, opts) do
      binding = [arn: arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_policy_versions, arn, binding)
    end

    def set_list_policy_versions_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_policy_versions, entries)
    end

    def list_policies_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_policies, :*, binding)
    end

    def set_list_policies_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_policies, entries)
    end

    def delete_policy_response(arn, opts) do
      binding = [arn: arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_policy, arn, binding)
    end

    def set_delete_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_policy, entries)
    end

    def attach_role_policy_response(role, policy_arn, opts) do
      binding = [role: role, policy_arn: policy_arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :attach_role_policy, role, binding)
    end

    def set_attach_role_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :attach_role_policy, entries)
    end

    def detach_role_policy_response(role, policy_arn, opts) do
      binding = [role: role, policy_arn: policy_arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :detach_role_policy, role, binding)
    end

    def set_detach_role_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :detach_role_policy, entries)
    end

    def list_attached_role_policies_response(role, opts) do
      binding = [role: role, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_attached_role_policies, role, binding)
    end

    def set_list_attached_role_policies_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_attached_role_policies, entries)
    end

    def attach_user_policy_response(user, policy_arn, opts) do
      binding = [user: user, policy_arn: policy_arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :attach_user_policy, user, binding)
    end

    def set_attach_user_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :attach_user_policy, entries)
    end

    def detach_user_policy_response(user, policy_arn, opts) do
      binding = [user: user, policy_arn: policy_arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :detach_user_policy, user, binding)
    end

    def set_detach_user_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :detach_user_policy, entries)
    end

    def attach_group_policy_response(group, policy_arn, opts) do
      binding = [group: group, policy_arn: policy_arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :attach_group_policy, group, binding)
    end

    def set_attach_group_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :attach_group_policy, entries)
    end

    def detach_group_policy_response(group, policy_arn, opts) do
      binding = [group: group, policy_arn: policy_arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :detach_group_policy, group, binding)
    end

    def set_detach_group_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :detach_group_policy, entries)
    end

    def list_mfa_devices_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_mfa_devices, :*, binding)
    end

    def set_list_mfa_devices_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_mfa_devices, entries)
    end

    def update_assume_role_policy_response(role_name, opts) do
      binding = [role_name: role_name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :update_assume_role_policy, role_name, binding)
    end

    def set_update_assume_role_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :update_assume_role_policy, entries)
    end

    def put_role_policy_response(role_name, policy_name, opts) do
      binding = [role_name: role_name, policy_name: policy_name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :put_role_policy, role_name, binding)
    end

    def set_put_role_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :put_role_policy, entries)
    end

    def get_role_policy_response(role_name, policy_name, opts) do
      binding = [role_name: role_name, policy_name: policy_name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_role_policy, role_name, binding)
    end

    def set_get_role_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_role_policy, entries)
    end

    def delete_role_policy_response(role_name, policy_name, opts) do
      binding = [role_name: role_name, policy_name: policy_name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_role_policy, role_name, binding)
    end

    def set_delete_role_policy_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_role_policy, entries)
    end

    def list_role_policies_response(role_name, opts) do
      binding = [role_name: role_name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_role_policies, role_name, binding)
    end

    def set_list_role_policies_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_role_policies, entries)
    end

    def create_open_id_connect_provider_response(url, opts) do
      binding = [url: url, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_open_id_connect_provider, url, binding)
    end

    def set_create_open_id_connect_provider_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_open_id_connect_provider, entries)
    end

    def get_open_id_connect_provider_response(arn, opts) do
      binding = [arn: arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_open_id_connect_provider, arn, binding)
    end

    def set_get_open_id_connect_provider_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_open_id_connect_provider, entries)
    end

    def list_open_id_connect_providers_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_open_id_connect_providers, :*, binding)
    end

    def set_list_open_id_connect_providers_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_open_id_connect_providers, entries)
    end

    def get_account_summary_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :get_account_summary, :*, binding)
    end

    def set_get_account_summary_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_account_summary, entries)
    end

    def delete_open_id_connect_provider_response(arn, opts) do
      binding = [arn: arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_open_id_connect_provider, arn, binding)
    end

    def set_delete_open_id_connect_provider_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_open_id_connect_provider, entries)
    end

    def update_open_id_connect_provider_thumbprint_response(arn, opts) do
      binding = [arn: arn, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :update_open_id_connect_provider_thumbprint,
        arn,
        binding
      )
    end

    def set_update_open_id_connect_provider_thumbprint_responses(entries) do
      Sandbox.register(
        @registry,
        __MODULE__,
        :update_open_id_connect_provider_thumbprint,
        entries
      )
    end

    def add_client_id_to_open_id_connect_provider_response(arn, opts) do
      binding = [arn: arn, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :add_client_id_to_open_id_connect_provider,
        arn,
        binding
      )
    end

    def set_add_client_id_to_open_id_connect_provider_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :add_client_id_to_open_id_connect_provider, entries)
    end

    def remove_client_id_from_open_id_connect_provider_response(arn, opts) do
      binding = [arn: arn, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :remove_client_id_from_open_id_connect_provider,
        arn,
        binding
      )
    end

    def set_remove_client_id_from_open_id_connect_provider_responses(entries) do
      Sandbox.register(
        @registry,
        __MODULE__,
        :remove_client_id_from_open_id_connect_provider,
        entries
      )
    end
  end
end
