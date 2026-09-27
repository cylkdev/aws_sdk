if Code.ensure_loaded?(SandboxRegistry) do
  defmodule AwsSDK.IdentityCenter.Sandbox do
    @moduledoc false

    @registry :aws_identity_center_sandbox

    alias AwsSDK.Sandbox

    def start_link, do: Sandbox.start_link(@registry)

    @spec disable_aws_identity_center_sandbox(map) :: :ok
    def disable_aws_identity_center_sandbox(_context),
      do: Sandbox.disable(@registry, __MODULE__)

    @spec sandbox_disabled? :: boolean
    def sandbox_disabled?, do: Sandbox.disabled?(@registry, __MODULE__)

    def list_instances_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_instances, :*, binding)
    end

    def set_list_instances_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_instances, entries)
    end

    def create_permission_set_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_permission_set, name, binding)
    end

    def set_create_permission_set_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_permission_set, entries)
    end

    def delete_permission_set_response(arn, opts) do
      binding = [arn: arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_permission_set, arn, binding)
    end

    def set_delete_permission_set_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_permission_set, entries)
    end

    def list_permission_sets_response(instance_arn, opts) do
      binding = [instance_arn: instance_arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_permission_sets, instance_arn, binding)
    end

    def set_list_permission_sets_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_permission_sets, entries)
    end

    def describe_permission_set_response(instance_arn, permission_set_arn, opts) do
      binding = [
        instance_arn: instance_arn,
        permission_set_arn: permission_set_arn,
        opts: opts
      ]

      Sandbox.apply(@registry, __MODULE__, :describe_permission_set, instance_arn, binding)
    end

    def set_describe_permission_set_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_permission_set, entries)
    end

    def get_inline_policy_for_permission_set_response(instance_arn, permission_set_arn, opts) do
      binding = [
        instance_arn: instance_arn,
        permission_set_arn: permission_set_arn,
        opts: opts
      ]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :get_inline_policy_for_permission_set,
        instance_arn,
        binding
      )
    end

    def set_get_inline_policy_for_permission_set_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :get_inline_policy_for_permission_set, entries)
    end

    def put_inline_policy_to_permission_set_response(
          instance_arn,
          permission_set_arn,
          policy,
          opts
        ) do
      binding = [
        instance_arn: instance_arn,
        permission_set_arn: permission_set_arn,
        policy: policy,
        opts: opts
      ]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :put_inline_policy_to_permission_set,
        instance_arn,
        binding
      )
    end

    def set_put_inline_policy_to_permission_set_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :put_inline_policy_to_permission_set, entries)
    end

    def list_managed_policies_in_permission_set_response(instance_arn, permission_set_arn, opts) do
      binding = [
        instance_arn: instance_arn,
        permission_set_arn: permission_set_arn,
        opts: opts
      ]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :list_managed_policies_in_permission_set,
        instance_arn,
        binding
      )
    end

    def set_list_managed_policies_in_permission_set_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_managed_policies_in_permission_set, entries)
    end

    def list_account_assignments_response(instance_arn, account_id, permission_set_arn, opts) do
      binding = [
        instance_arn: instance_arn,
        account_id: account_id,
        permission_set_arn: permission_set_arn,
        opts: opts
      ]

      Sandbox.apply(@registry, __MODULE__, :list_account_assignments, instance_arn, binding)
    end

    def set_list_account_assignments_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_account_assignments, entries)
    end

    def list_accounts_for_provisioned_permission_set_response(
          instance_arn,
          permission_set_arn,
          opts
        ) do
      binding = [
        instance_arn: instance_arn,
        permission_set_arn: permission_set_arn,
        opts: opts
      ]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :list_accounts_for_provisioned_permission_set,
        instance_arn,
        binding
      )
    end

    def set_list_accounts_for_provisioned_permission_set_responses(entries) do
      Sandbox.register(
        @registry,
        __MODULE__,
        :list_accounts_for_provisioned_permission_set,
        entries
      )
    end

    def attach_managed_policy_to_permission_set_response(ps_arn, opts) do
      binding = [ps_arn: ps_arn, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :attach_managed_policy_to_permission_set,
        ps_arn,
        binding
      )
    end

    def set_attach_managed_policy_to_permission_set_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :attach_managed_policy_to_permission_set, entries)
    end

    def detach_managed_policy_from_permission_set_response(ps_arn, opts) do
      binding = [ps_arn: ps_arn, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :detach_managed_policy_from_permission_set,
        ps_arn,
        binding
      )
    end

    def set_detach_managed_policy_from_permission_set_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :detach_managed_policy_from_permission_set, entries)
    end

    def create_account_assignment_response(instance_arn, opts) do
      binding = [instance_arn: instance_arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_account_assignment, instance_arn, binding)
    end

    def set_create_account_assignment_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_account_assignment, entries)
    end

    def delete_account_assignment_response(instance_arn, opts) do
      binding = [instance_arn: instance_arn, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_account_assignment, instance_arn, binding)
    end

    def set_delete_account_assignment_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_account_assignment, entries)
    end

    def provision_permission_set_response(permission_set_arn, opts) do
      binding = [permission_set_arn: permission_set_arn, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :provision_permission_set,
        permission_set_arn,
        binding
      )
    end

    def set_provision_permission_set_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :provision_permission_set, entries)
    end

    def create_identity_store_user_response(username, opts) do
      binding = [username: username, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_identity_store_user, username, binding)
    end

    def set_create_identity_store_user_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_identity_store_user, entries)
    end

    def delete_identity_store_user_response(user_id, opts) do
      binding = [user_id: user_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_identity_store_user, user_id, binding)
    end

    def set_delete_identity_store_user_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_identity_store_user, entries)
    end

    def update_identity_store_user_response(user_id, opts) do
      binding = [user_id: user_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :update_identity_store_user, user_id, binding)
    end

    def set_update_identity_store_user_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :update_identity_store_user, entries)
    end

    def describe_identity_store_user_response(user_id, opts) do
      binding = [user_id: user_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_identity_store_user, user_id, binding)
    end

    def set_describe_identity_store_user_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_identity_store_user, entries)
    end

    def describe_identity_store_group_response(group_id, opts) do
      binding = [group_id: group_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_identity_store_group, group_id, binding)
    end

    def set_describe_identity_store_group_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_identity_store_group, entries)
    end

    def list_identity_store_users_response(store_id, opts) do
      binding = [store_id: store_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_identity_store_users, store_id, binding)
    end

    def set_list_identity_store_users_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_identity_store_users, entries)
    end

    def create_identity_store_group_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_identity_store_group, name, binding)
    end

    def set_create_identity_store_group_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_identity_store_group, entries)
    end

    def delete_identity_store_group_response(group_id, opts) do
      binding = [group_id: group_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_identity_store_group, group_id, binding)
    end

    def set_delete_identity_store_group_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_identity_store_group, entries)
    end

    def list_identity_store_groups_response(store_id, opts) do
      binding = [store_id: store_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_identity_store_groups, store_id, binding)
    end

    def set_list_identity_store_groups_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_identity_store_groups, entries)
    end

    def create_group_membership_response(group_id, opts) do
      binding = [group_id: group_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_group_membership, group_id, binding)
    end

    def set_create_group_membership_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_group_membership, entries)
    end

    def delete_group_membership_response(membership_id, opts) do
      binding = [membership_id: membership_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_group_membership, membership_id, binding)
    end

    def set_delete_group_membership_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_group_membership, entries)
    end
  end
end
