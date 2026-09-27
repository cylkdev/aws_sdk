if Code.ensure_loaded?(SandboxRegistry) do
  defmodule AwsSDK.Organizations.Sandbox do
    @moduledoc false

    @registry :aws_organizations_sandbox

    alias AwsSDK.Sandbox

    def start_link, do: Sandbox.start_link(@registry)

    @spec disable_aws_organizations_sandbox(map) :: :ok
    def disable_aws_organizations_sandbox(_context),
      do: Sandbox.disable(@registry, __MODULE__)

    @spec sandbox_disabled? :: boolean
    def sandbox_disabled?, do: Sandbox.disabled?(@registry, __MODULE__)

    def create_organization_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_organization, :*, binding)
    end

    def set_create_organization_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_organization, entries)
    end

    def delete_organization_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_organization, :*, binding)
    end

    def set_delete_organization_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_organization, entries)
    end

    def describe_organization_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_organization, :*, binding)
    end

    def set_describe_organization_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_organization, entries)
    end

    def create_organizational_unit_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_organizational_unit, name, binding)
    end

    def set_create_organizational_unit_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_organizational_unit, entries)
    end

    def delete_organizational_unit_response(ou_id, opts) do
      binding = [ou_id: ou_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :delete_organizational_unit, ou_id, binding)
    end

    def set_delete_organizational_unit_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :delete_organizational_unit, entries)
    end

    def list_organizational_units_for_parent_response(parent_id, opts) do
      binding = [parent_id: parent_id, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :list_organizational_units_for_parent,
        parent_id,
        binding
      )
    end

    def set_list_organizational_units_for_parent_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_organizational_units_for_parent, entries)
    end

    def create_account_response(name, opts) do
      binding = [name: name, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :create_account, name, binding)
    end

    def set_create_account_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :create_account, entries)
    end

    def describe_create_account_status_response(request_id, opts) do
      binding = [request_id: request_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_create_account_status, request_id, binding)
    end

    def set_describe_create_account_status_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_create_account_status, entries)
    end

    def move_account_response(account_id, opts) do
      binding = [account_id: account_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :move_account, account_id, binding)
    end

    def set_move_account_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :move_account, entries)
    end

    def close_account_response(account_id, opts) do
      binding = [account_id: account_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :close_account, account_id, binding)
    end

    def set_close_account_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :close_account, entries)
    end

    def list_accounts_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_accounts, :*, binding)
    end

    def set_list_accounts_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_accounts, entries)
    end

    def list_roots_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_roots, :*, binding)
    end

    def set_list_roots_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_roots, entries)
    end

    def register_delegated_administrator_response(account_id, opts) do
      binding = [account_id: account_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :register_delegated_administrator, account_id, binding)
    end

    def set_register_delegated_administrator_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :register_delegated_administrator, entries)
    end

    def enable_aws_service_access_response(service_principal, opts) do
      binding = [service_principal: service_principal, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :enable_aws_service_access,
        service_principal,
        binding
      )
    end

    def set_enable_aws_service_access_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :enable_aws_service_access, entries)
    end

    def list_delegated_administrators_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_delegated_administrators, :*, binding)
    end

    def set_list_delegated_administrators_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_delegated_administrators, entries)
    end

    def list_aws_service_access_for_organization_response(opts) do
      binding = [opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :list_aws_service_access_for_organization,
        :*,
        binding
      )
    end

    def set_list_aws_service_access_for_organization_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_aws_service_access_for_organization, entries)
    end

    def list_parents_response(child_id, opts) do
      binding = [child_id: child_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_parents, child_id, binding)
    end

    def set_list_parents_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_parents, entries)
    end

    def describe_account_response(account_id, opts) do
      binding = [account_id: account_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_account, account_id, binding)
    end

    def set_describe_account_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_account, entries)
    end

    def describe_organizational_unit_response(ou_id, opts) do
      binding = [ou_id: ou_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :describe_organizational_unit, ou_id, binding)
    end

    def set_describe_organizational_unit_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :describe_organizational_unit, entries)
    end

    def update_organizational_unit_response(ou_id, opts) do
      binding = [ou_id: ou_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :update_organizational_unit, ou_id, binding)
    end

    def set_update_organizational_unit_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :update_organizational_unit, entries)
    end

    def disable_aws_service_access_response(service_principal, opts) do
      binding = [service_principal: service_principal, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :disable_aws_service_access,
        service_principal,
        binding
      )
    end

    def set_disable_aws_service_access_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :disable_aws_service_access, entries)
    end

    def deregister_delegated_administrator_response(account_id, opts) do
      binding = [account_id: account_id, opts: opts]

      Sandbox.apply(
        @registry,
        __MODULE__,
        :deregister_delegated_administrator,
        account_id,
        binding
      )
    end

    def set_deregister_delegated_administrator_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :deregister_delegated_administrator, entries)
    end

    def list_children_response(parent_id, opts) do
      binding = [parent_id: parent_id, opts: opts]

      Sandbox.apply(@registry, __MODULE__, :list_children, parent_id, binding)
    end

    def set_list_children_responses(entries) do
      Sandbox.register(@registry, __MODULE__, :list_children, entries)
    end
  end
end
