defmodule AwsSDK.Organizations do
  @moduledoc """
  `AwsSDK.Organizations` provides an API for AWS Organizations.

  This module calls the AWS Organizations JSON 1.1 API directly via
  `AwsSDK.HTTP` and `AwsSDK.Signer` (through `AwsSDK.Organizations.Client`).
  Organizations is a global service — all requests are routed to
  `us-east-1` regardless of the configured region.

  ## Shared Options

  Credentials and region are flat top-level opts on every call (ex_aws shape).
  Each accepts a literal, a source tuple, or a list of sources (first
  non-nil wins):

    - `:access_key_id`, `:secret_access_key`, `:security_token`, `:region` -
      Sources: literal binary, `{:system, "ENV"}`, `:instance_role`,
      `:ecs_task_role`, `{:awscli, profile}` / `{:awscli, profile, ttl}`,
      a module, or a list of any of these. Map-returning sources merge
      into the outer config. `{:awscli, _}` is not in the default chain —
      callers opt in explicitly.

  Organizations is a global service; requests always go to `us-east-1`.
  The `:region` opt is used only for SigV4 signing and defaults to
  `"us-east-1"`.

  The following options are also available:

    - `:organizations` - A keyword list of Organizations endpoint overrides.
      Supported keys: `:scheme`, `:host`, `:port`. Credentials are not
      read from this sub-list; use the top-level keys above.

    - `:sandbox` - A keyword list to override sandbox configuration.
        - `:enabled` - Whether sandbox mode is enabled.
        - `:scheme` - The sandbox scheme.
        - `:host` - The sandbox host.
        - `:port` - The sandbox port.

  ## Sandbox

  Set `sandbox: [enabled: true]` to activate sandbox mode.

  ### Setup

  Add the following to your `test_helper.exs`:

      AwsSDK.Organizations.Sandbox.start_link()

  ### Usage

      setup do
        AwsSDK.Organizations.Sandbox.set_list_accounts_responses([
          fn -> {:ok, %{accounts: [%{id: "111122223333", name: "tools"}]}} end
        ])
      end

      test "lists accounts" do
        assert {:ok, %{accounts: [%{id: "111122223333"}]}} =
                 AwsSDK.Organizations.list_accounts(sandbox: [enabled: true])
      end
  """

  alias AwsSDK.Client
  alias AwsSDK.Operation
  alias ExUtils.Serializer

  @service "organizations"
  @content_type "application/x-amz-json-1.1"
  @target_prefix "AWSOrganizationsV20161128"
  @default_region "us-east-1"

  # ---------------------------------------------------------------------------
  # Organization
  # ---------------------------------------------------------------------------

  @doc """
  Creates an AWS Organization with all features enabled.

  ## Phase

  Phase 2 — AWS Organizations setup. Must be called once from the management
  account root user before any other Organizations operations.

  ## Options

    * `:feature_set` - `"ALL"` (default) or `"CONSOLIDATED_BILLING"`.

  ## Examples

      AwsSDK.Organizations.create_organization(feature_set: "ALL")
      #=> {:ok,
      #=>  %{
      #=>    organization: %{
      #=>      id: "o-exampleorgid",
      #=>      arn: "arn:aws:organizations::123456789012:organization/o-exampleorgid",
      #=>      feature_set: "ALL",
      #=>      master_account_arn: "arn:aws:organizations::123456789012:account/o-exampleorgid/123456789012",
      #=>      master_account_id: "123456789012",
      #=>      master_account_email: "root@example.com",
      #=>      available_policy_types: [%{type: "SERVICE_CONTROL_POLICY", status: "ENABLED"}]
      #=>    }
      #=>  }}
  """
  @spec create_organization(opts :: keyword()) :: {:ok, %{organization: map()}} | {:error, term()}
  def create_organization(opts \\ []) do
    if sandbox?(opts) do
      sandbox_create_organization_response(opts)
    else
      do_create_organization(opts)
    end
  end

  defp do_create_organization(opts) do
    data = maybe_put(%{}, "FeatureSet", opts[:feature_set])

    with {:ok, op} <- build_operation("CreateOrganization", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Creates an Organizational Unit (OU) under a parent root or OU.

  ## Phase

  Phase 2 — AWS Organizations setup. Call after `create_organization/1`
  to build the OU structure: Management OU, Workloads OU, Tools OU, Clients OU.

  ## Arguments

    * `parent_id` - The ID of the root (`"r-xxxx"`) or parent OU (`"ou-xxxx-yyyyyyyy"`).
    * `name` - The name for the new OU.
    * `opts` - Shared options.

  Returns `{:ok, %{organizational_unit: %{id, arn, name}}}`.

  ## Examples

      AwsSDK.Organizations.create_organizational_unit("r-exam", "Workloads")
      #=> {:ok,
      #=>  %{
      #=>    organizational_unit: %{
      #=>      id: "ou-exam-awsccdev",
      #=>      arn: "arn:aws:organizations::123456789012:ou/o-exampleorgid/ou-exam-awsccdev",
      #=>      name: "Workloads"
      #=>    }
      #=>  }}
  """
  @spec create_organizational_unit(parent_id :: String.t(), name :: String.t(), opts :: keyword()) ::
          {:ok, %{organizational_unit: map()}} | {:error, term()}
  def create_organizational_unit(parent_id, name, opts \\ [])
      when is_binary(parent_id) and is_binary(name) do
    if sandbox?(opts) do
      sandbox_create_organizational_unit_response(name, opts)
    else
      do_create_organizational_unit(parent_id, name, opts)
    end
  end

  defp do_create_organizational_unit(parent_id, name, opts) do
    with {:ok, op} <-
           build_operation(
             "CreateOrganizationalUnit",
             %{"ParentId" => parent_id, "Name" => name},
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Initiates creation of a new member account in the organization.

  ## Phase

  Phase 2 — AWS Organizations setup. Creates the `tools` and `billing` member accounts.
  Account creation is asynchronous — poll `describe_create_account_status/2` until
  the state is `"SUCCEEDED"` or `"FAILED"`.

  ## Arguments

    * `name` - The display name for the account (e.g. `"tools"`).
    * `email` - The root email address for the account (must be unique across AWS).
    * `opts` - Options including `:iam_user_access_to_billing` (`"ALLOW"` | `"DENY"`).

  Returns `{:ok, %{create_account_status: %{id, state, account_name, ...}}}`.

  ## Examples

      AwsSDK.Organizations.create_account("tools", "aws+tools@example.com")
      #=> {:ok,
      #=>  %{
      #=>    create_account_status: %{
      #=>      id: "car-exampleaccountcreationrequestid",
      #=>      account_name: "tools",
      #=>      state: "IN_PROGRESS",
      #=>      requested_timestamp: 1.7e9
      #=>    }
      #=>  }}

  Creation is asynchronous. Poll `describe_create_account_status/2` with the
  returned `:id` until `:state` is `"SUCCEEDED"` or `"FAILED"`.
  """
  @spec create_account(name :: String.t(), email :: String.t(), opts :: keyword()) ::
          {:ok, %{create_account_status: map()}} | {:error, term()}
  def create_account(name, email, opts \\ []) when is_binary(name) and is_binary(email) do
    if sandbox?(opts) do
      sandbox_create_account_response(name, opts)
    else
      do_create_account(name, email, opts)
    end
  end

  defp do_create_account(name, email, opts) do
    data =
      maybe_put(
        %{"AccountName" => name, "Email" => email},
        "IamUserAccessToBilling",
        opts[:iam_user_access_to_billing]
      )

    with {:ok, op} <- build_operation("CreateAccount", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Returns the current status of an account creation request.

  ## Phase

  Phase 2 — AWS Organizations setup. Poll after `create_account/3` until
  `state` is `"SUCCEEDED"` (contains `account_id`) or `"FAILED"` (contains `failure_reason`).

  ## Arguments

    * `request_id` - The `id` from the `create_account_status` returned by `create_account/3`.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.Organizations.describe_create_account_status("car-exampleaccountcreationrequestid")
      #=> {:ok,
      #=>  %{
      #=>    create_account_status: %{
      #=>      id: "car-exampleaccountcreationrequestid",
      #=>      account_name: "tools",
      #=>      state: "SUCCEEDED",
      #=>      account_id: "333333333333",
      #=>      requested_timestamp: 1.7e9,
      #=>      completed_timestamp: 1.7e9
      #=>    }
      #=>  }}

      # On failure, :failure_reason replaces :account_id.
      #=> {:ok,
      #=>  %{
      #=>    create_account_status: %{
      #=>      state: "FAILED",
      #=>      failure_reason: "EMAIL_ALREADY_EXISTS"
      #=>    }
      #=>  }}
  """
  @spec describe_create_account_status(request_id :: String.t(), opts :: keyword()) ::
          {:ok, %{create_account_status: map()}} | {:error, term()}
  def describe_create_account_status(request_id, opts \\ []) when is_binary(request_id) do
    if sandbox?(opts) do
      sandbox_describe_create_account_status_response(request_id, opts)
    else
      do_describe_create_account_status(request_id, opts)
    end
  end

  defp do_describe_create_account_status(request_id, opts) do
    with {:ok, op} <-
           build_operation(
             "DescribeCreateAccountStatus",
             %{"CreateAccountRequestId" => request_id},
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Moves an account from one OU (or root) to another.

  ## Phase

  Phase 2 — AWS Organizations setup. Moves newly created accounts from the root
  into the appropriate OU after account creation succeeds.

  ## Arguments

    * `account_id` - The 12-digit ID of the account to move.
    * `source_parent_id` - The current parent ID (root or OU).
    * `destination_parent_id` - The target parent ID (root or OU).
    * `opts` - Shared options.

  ## Examples

      AwsSDK.Organizations.move_account("333333333333", "r-exam", "ou-exam-awsccdev")
      #=> {:ok, %{}}
  """
  @spec move_account(
          account_id :: String.t(),
          source_parent_id :: String.t(),
          destination_parent_id :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{}} | {:error, term()}
  def move_account(account_id, source_parent_id, destination_parent_id, opts \\ [])
      when is_binary(account_id) and is_binary(source_parent_id) and
             is_binary(destination_parent_id) do
    if sandbox?(opts) do
      sandbox_move_account_response(account_id, opts)
    else
      do_move_account(account_id, source_parent_id, destination_parent_id, opts)
    end
  end

  defp do_move_account(account_id, source_parent_id, destination_parent_id, opts) do
    data = %{
      "AccountId" => account_id,
      "SourceParentId" => source_parent_id,
      "DestinationParentId" => destination_parent_id
    }

    with {:ok, op} <- build_operation("MoveAccount", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deletes the organization. The organization must be empty: no member accounts,
  no OUs, and no policies. AWS rejects the request otherwise.

  ## Arguments

    * `opts` - Shared options.

  ## Examples

      AwsSDK.Organizations.delete_organization()
      #=> {:ok, %{}}

  Every member account must be removed first.
  """
  @spec delete_organization(opts :: keyword()) :: {:ok, %{}} | {:error, term()}
  def delete_organization(opts \\ []) do
    if sandbox?(opts) do
      sandbox_delete_organization_response(opts)
    else
      do_delete_organization(opts)
    end
  end

  defp do_delete_organization(opts) do
    with {:ok, op} <- build_operation("DeleteOrganization", %{}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deletes an Organizational Unit. The OU must be empty (no child accounts or OUs
  and no attached policies). AWS rejects the request otherwise.

  ## Arguments

    * `ou_id` - The ID of the OU to delete (`"ou-xxxx-yyyyyyyy"`).
    * `opts` - Shared options.

  ## Examples

      AwsSDK.Organizations.delete_organizational_unit("ou-exam-awsccdev")
      #=> {:ok, %{}}

  The OU must contain no accounts or child OUs.
  """
  @spec delete_organizational_unit(ou_id :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def delete_organizational_unit(ou_id, opts \\ []) when is_binary(ou_id) do
    if sandbox?(opts) do
      sandbox_delete_organizational_unit_response(ou_id, opts)
    else
      do_delete_organizational_unit(ou_id, opts)
    end
  end

  defp do_delete_organizational_unit(ou_id, opts) do
    with {:ok, op} <-
           build_operation("DeleteOrganizationalUnit", %{"OrganizationalUnitId" => ou_id}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Closes a member account, scheduling it for permanent deletion.

  Initiates the AWS account closure process. The account enters a
  suspended state for 90 days before being permanently deleted. The
  account must be a member of the organization (not the management
  account).

  ## Arguments

    * `account_id` - The 12-digit ID of the account to close.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.Organizations.close_account("333333333333")
      #=> {:ok, %{}}

  Closure is asynchronous and not reversible through this API.
  """
  @spec close_account(account_id :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def close_account(account_id, opts \\ []) when is_binary(account_id) do
    if sandbox?(opts) do
      sandbox_close_account_response(account_id, opts)
    else
      do_close_account(account_id, opts)
    end
  end

  defp do_close_account(account_id, opts) do
    with {:ok, op} <- build_operation("CloseAccount", %{"AccountId" => account_id}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Registers a member account as a delegated administrator for a service.

  ## Phase

  Phase 3 — Billing delegation. Call once per billing service principal to
  delegate billing management to the billing account:
  - `"billing.amazonaws.com"`
  - `"ce.amazonaws.com"`
  - `"budgets.amazonaws.com"`
  - `"cur.amazonaws.com"`

  ## Arguments

    * `account_id` - The 12-digit ID of the account to register.
    * `service_principal` - The AWS service principal to delegate (e.g. `"billing.amazonaws.com"`).
    * `opts` - Shared options.

  ## Examples

      AwsSDK.Organizations.register_delegated_administrator(
        "333333333333",
        "sso.amazonaws.com"
      )
      #=> {:ok, %{}}
  """
  @spec register_delegated_administrator(
          account_id :: String.t(),
          service_principal :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{}} | {:error, term()}
  def register_delegated_administrator(account_id, service_principal, opts \\ [])
      when is_binary(account_id) and is_binary(service_principal) do
    if sandbox?(opts) do
      sandbox_register_delegated_administrator_response(account_id, opts)
    else
      do_register_delegated_administrator(account_id, service_principal, opts)
    end
  end

  defp do_register_delegated_administrator(account_id, service_principal, opts) do
    data = %{"AccountId" => account_id, "ServicePrincipal" => service_principal}

    with {:ok, op} <- build_operation("RegisterDelegatedAdministrator", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Enables trusted access for an AWS service in the organization.

  ## Phase

  Phase 2 — AWS Organizations setup, Step 8. Call with `"sso.amazonaws.com"` to
  enable trusted access for IAM Identity Center before activating it.

  ## Arguments

    * `service_principal` - The AWS service principal to enable (e.g. `"sso.amazonaws.com"`).
    * `opts` - Shared options.

  ## Examples

      AwsSDK.Organizations.enable_aws_service_access("sso.amazonaws.com")
      #=> {:ok, %{}}
  """
  @spec enable_aws_service_access(service_principal :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def enable_aws_service_access(service_principal, opts \\ [])
      when is_binary(service_principal) do
    if sandbox?(opts) do
      sandbox_enable_aws_service_access_response(service_principal, opts)
    else
      do_enable_aws_service_access(service_principal, opts)
    end
  end

  defp do_enable_aws_service_access(service_principal, opts) do
    with {:ok, op} <-
           build_operation(
             "EnableAWSServiceAccess",
             %{"ServicePrincipal" => service_principal},
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Returns metadata about the current organization, including feature set.

  Returns `{:ok, %{organization: map()}}`. The `organization` map includes
  `:id`, `:arn`, `:feature_set` (`"ALL"` or `"CONSOLIDATED_BILLING"`), and more.

  ## Examples

      AwsSDK.Organizations.describe_organization()
      #=> {:ok,
      #=>  %{
      #=>    organization: %{
      #=>      id: "o-exampleorgid",
      #=>      arn: "arn:aws:organizations::123456789012:organization/o-exampleorgid",
      #=>      feature_set: "ALL",
      #=>      master_account_arn: "arn:aws:organizations::123456789012:account/o-exampleorgid/123456789012",
      #=>      master_account_id: "123456789012",
      #=>      master_account_email: "root@example.com",
      #=>      available_policy_types: [%{type: "SERVICE_CONTROL_POLICY", status: "ENABLED"}]
      #=>    }
      #=>  }}
  """
  @spec describe_organization(opts :: keyword()) ::
          {:ok, %{organization: map()}} | {:error, term()}
  def describe_organization(opts \\ []) do
    if sandbox?(opts) do
      sandbox_describe_organization_response(opts)
    else
      do_describe_organization(opts)
    end
  end

  defp do_describe_organization(opts) do
    with {:ok, op} <- build_operation("DescribeOrganization", %{}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Roots
  # ---------------------------------------------------------------------------

  @doc """
  Returns the primary root in the current organization.

  Returns `{:ok, root}` where root is the first root in the list, or `{:error, term()}` on failure.

  ## Examples

      AwsSDK.Organizations.get_root()
      #=> {:ok,
      #=>  %{
      #=>    id: "r-exam",
      #=>    arn: "arn:aws:organizations::123456789012:root/o-exampleorgid/r-exam",
      #=>    name: "Root",
      #=>    policy_types: [%{type: "SERVICE_CONTROL_POLICY", status: "ENABLED"}]
      #=>  }}

  A convenience wrapper returning the first element of `list_roots/1`; an
  organization has exactly one root today.
  """
  def get_root(opts \\ []) do
    case list_roots(opts) do
      {:ok, %{roots: [root | _]}} -> {:ok, root}
      other -> other
    end
  end

  @doc """
  Lists all roots in the current organization.

  Returns AWS's `ListRoots` response unchanged: `:roots` plus `:next_token`.

  ## Examples

      AwsSDK.Organizations.list_roots()
      #=> {:ok,
      #=>  %{
      #=>    roots: [
      #=>      %{
      #=>        id: "r-exam",
      #=>        arn: "arn:aws:organizations::123456789012:root/o-exampleorgid/r-exam",
      #=>        name: "Root",
      #=>        policy_types: [%{type: "SERVICE_CONTROL_POLICY", status: "ENABLED"}]
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec list_roots(opts :: keyword()) :: {:ok, map()} | {:error, term()}
  def list_roots(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_roots_response(opts)
    else
      do_list_roots(opts)
    end
  end

  defp do_list_roots(opts) do
    # ListRoots accepts NextToken and MaxResults; neither was sent and the
    # returned NextToken was discarded. AWS documents that a List* call can
    # return an empty page with a non-null NextToken, so this could report no
    # roots while roots existed.
    data =
      %{}
      |> maybe_put("NextToken", opts[:next_token])
      |> maybe_put("MaxResults", opts[:max_results])

    with {:ok, op} <- build_operation("ListRoots", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Organizational Units
  # ---------------------------------------------------------------------------

  @doc """
  Lists the organizational units (OUs) directly under a given parent.

  ## Arguments

    * `parent_id` - The ID of the root or parent OU (e.g. `"r-xxxx"` or `"ou-xxxx-yyyyyyyy"`).
    * `opts` - Options including `:next_token`, `:max_results`, plus shared options.

  Returns AWS's `ListOrganizationalUnitsForParent` response unchanged:
  `:organizational_units` plus `:next_token`.

  ## Examples

      AwsSDK.Organizations.list_organizational_units_for_parent("r-exam")
      #=> {:ok,
      #=>  %{
      #=>    organizational_units: [
      #=>      %{
      #=>        id: "ou-exam-awsccdev",
      #=>        arn: "arn:aws:organizations::123456789012:ou/o-exampleorgid/ou-exam-awsccdev",
      #=>        name: "Workloads"
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}

  Direct children only -- nested OUs need a call per level.
  """
  @spec list_organizational_units_for_parent(parent_id :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def list_organizational_units_for_parent(parent_id, opts \\ []) when is_binary(parent_id) do
    if sandbox?(opts) do
      sandbox_list_organizational_units_for_parent_response(parent_id, opts)
    else
      do_list_organizational_units_for_parent(parent_id, opts)
    end
  end

  defp do_list_organizational_units_for_parent(parent_id, opts) do
    data =
      %{"ParentId" => parent_id}
      |> maybe_put("NextToken", opts[:next_token])
      |> maybe_put("MaxResults", opts[:max_results])

    with {:ok, op} <- build_operation("ListOrganizationalUnitsForParent", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts
  # ---------------------------------------------------------------------------

  @doc """
  Lists all AWS accounts in the organization.

  Returns `{:ok, %{accounts: [map()]}}` where each account has `:id`, `:arn`,
  `:name`, `:email`, `:status`.

  ## Examples

      AwsSDK.Organizations.list_accounts()
      #=> {:ok,
      #=>  %{
      #=>    accounts: [
      #=>      %{
      #=>        id: "333333333333",
      #=>        arn: "arn:aws:organizations::123456789012:account/o-exampleorgid/333333333333",
      #=>        name: "tools",
      #=>        email: "aws+tools@example.com",
      #=>        status: "ACTIVE",
      #=>        joined_method: "CREATED",
      #=>        joined_timestamp: 1.7e9
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}

  Every account in the organization, regardless of OU. Use `list_children/2`
  to scope to one parent.
  """
  @spec list_accounts(opts :: keyword()) ::
          {:ok, %{accounts: list(map()), next_token: String.t() | nil}} | {:error, term()}
  def list_accounts(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_accounts_response(opts)
    else
      do_list_accounts(opts)
    end
  end

  defp do_list_accounts(opts) do
    data =
      %{}
      |> maybe_put("NextToken", opts[:next_token])
      |> maybe_put("MaxResults", opts[:max_results])

    with {:ok, op} <- build_operation("ListAccounts", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Delegated administrators
  # ---------------------------------------------------------------------------

  @doc """
  Lists the delegated administrator accounts for the organization.

  ## Options

    * `:service_principal` - Filter by service principal (e.g. `"billing.amazonaws.com"`).
    * `:next_token` - Pagination token.
    * `:max_results` - Maximum number of results.

  Returns `{:ok, %{delegated_administrators: [map()]}}` where each entry has
  `:id`, `:arn`, `:name`, `:email`, `:status`, `:delegation_enabled_date`.

  ## Examples

      AwsSDK.Organizations.list_delegated_administrators(service_principal: "sso.amazonaws.com")
      #=> {:ok,
      #=>  %{
      #=>    delegated_administrators: [
      #=>      %{
      #=>        id: "333333333333",
      #=>        arn: "arn:aws:organizations::123456789012:account/o-exampleorgid/333333333333",
      #=>        name: "tools",
      #=>        email: "aws+tools@example.com",
      #=>        status: "ACTIVE",
      #=>        delegation_enabled_date: 1.7e9
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec list_delegated_administrators(opts :: keyword()) ::
          {:ok, %{delegated_administrators: list(map())}} | {:error, term()}
  def list_delegated_administrators(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_delegated_administrators_response(opts)
    else
      do_list_delegated_administrators(opts)
    end
  end

  defp do_list_delegated_administrators(opts) do
    data =
      %{}
      |> maybe_put("ServicePrincipal", opts[:service_principal])
      |> maybe_put("NextToken", opts[:next_token])
      |> maybe_put("MaxResults", opts[:max_results])

    with {:ok, op} <- build_operation("ListDelegatedAdministrators", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Service access (trusted services)
  # ---------------------------------------------------------------------------

  @doc """
  Lists the AWS services that have trusted access enabled for the organization.

  Returns `{:ok, %{enabled_service_principals: [map()], next_token: String.t() | nil}}`
  where each entry has `:service_principal` (e.g. `"sso.amazonaws.com"`) and
  `:date_enabled`. Pass the returned `:next_token` back via `opts[:next_token]`
  to fetch subsequent pages.

  ## Examples

      AwsSDK.Organizations.list_aws_service_access_for_organization()
      #=> {:ok,
      #=>  %{
      #=>    enabled_service_principals: [
      #=>      %{service_principal: "sso.amazonaws.com", date_enabled: 1.7e9}
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec list_aws_service_access_for_organization(opts :: keyword()) ::
          {:ok, %{enabled_service_principals: list(map()), next_token: String.t() | nil}}
          | {:error, term()}
  def list_aws_service_access_for_organization(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_aws_service_access_for_organization_response(opts)
    else
      do_list_aws_service_access_for_organization(opts)
    end
  end

  defp do_list_aws_service_access_for_organization(opts) do
    data =
      %{}
      |> maybe_put("NextToken", opts[:next_token])
      |> maybe_put("MaxResults", opts[:max_results])

    with {:ok, op} <- build_operation("ListAWSServiceAccessForOrganization", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Parents
  # ---------------------------------------------------------------------------

  @doc """
  Lists the parents (root or OU) of an account or OU. Always returns zero or
  one parent for AWS Organizations.

  Returns `{:ok, %{parents: [map()], next_token: String.t() | nil}}` where each
  parent has `:id` and `:type` (`"ROOT"` or `"ORGANIZATIONAL_UNIT"`).

  ## Examples

      AwsSDK.Organizations.list_parents("333333333333")
      #=> {:ok,
      #=>  %{
      #=>    parents: [%{id: "ou-exam-awsccdev", type: "ORGANIZATIONAL_UNIT"}],
      #=>    next_token: nil
      #=>  }}

  Always zero or one parent; `:type` is `"ROOT"` or `"ORGANIZATIONAL_UNIT"`.
  """
  @spec list_parents(child_id :: String.t(), opts :: keyword()) ::
          {:ok, %{parents: list(map()), next_token: String.t() | nil}} | {:error, term()}
  def list_parents(child_id, opts \\ []) when is_binary(child_id) do
    if sandbox?(opts) do
      sandbox_list_parents_response(child_id, opts)
    else
      do_list_parents(child_id, opts)
    end
  end

  defp do_list_parents(child_id, opts) do
    data =
      %{"ChildId" => child_id}
      |> maybe_put("NextToken", opts[:next_token])
      |> maybe_put("MaxResults", opts[:max_results])

    with {:ok, op} <- build_operation("ListParents", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Describe / update
  # ---------------------------------------------------------------------------

  @doc """
  Describes a single AWS account.

  ## Arguments

    * `account_id` - The 12-digit AWS account ID.
    * `opts` - Shared options.

  Returns `{:ok, %{account: map()}}` where the account map has `:id`, `:arn`,
  `:name`, `:email`, `:status`, `:joined_method`, `:joined_timestamp`.

  ## Examples

      AwsSDK.Organizations.describe_account("333333333333")
      #=> {:ok,
      #=>  %{
      #=>    account: %{
      #=>      id: "333333333333",
      #=>      arn: "arn:aws:organizations::123456789012:account/o-exampleorgid/333333333333",
      #=>      name: "tools",
      #=>      email: "aws+tools@example.com",
      #=>      status: "ACTIVE",
      #=>      joined_method: "CREATED",
      #=>      joined_timestamp: 1.7e9
      #=>    }
      #=>  }}
  """
  @spec describe_account(account_id :: String.t(), opts :: keyword()) ::
          {:ok, %{account: map()}} | {:error, term()}
  def describe_account(account_id, opts \\ []) when is_binary(account_id) do
    if sandbox?(opts) do
      sandbox_describe_account_response(account_id, opts)
    else
      do_describe_account(account_id, opts)
    end
  end

  defp do_describe_account(account_id, opts) do
    with {:ok, op} <- build_operation("DescribeAccount", %{"AccountId" => account_id}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Describes a single Organizational Unit.

  ## Arguments

    * `ou_id` - The OU ID (`"ou-xxxx-yyyyyyyy"`).
    * `opts` - Shared options.

  Returns `{:ok, %{organizational_unit: map()}}` where the OU map has `:id`,
  `:arn`, `:name`.

  ## Examples

      AwsSDK.Organizations.describe_organizational_unit("ou-exam-awsccdev")
      #=> {:ok,
      #=>  %{
      #=>    organizational_unit: %{
      #=>      id: "ou-exam-awsccdev",
      #=>      arn: "arn:aws:organizations::123456789012:ou/o-exampleorgid/ou-exam-awsccdev",
      #=>      name: "Workloads"
      #=>    }
      #=>  }}
  """
  @spec describe_organizational_unit(ou_id :: String.t(), opts :: keyword()) ::
          {:ok, %{organizational_unit: map()}} | {:error, term()}
  def describe_organizational_unit(ou_id, opts \\ []) when is_binary(ou_id) do
    if sandbox?(opts) do
      sandbox_describe_organizational_unit_response(ou_id, opts)
    else
      do_describe_organizational_unit(ou_id, opts)
    end
  end

  defp do_describe_organizational_unit(ou_id, opts) do
    with {:ok, op} <-
           build_operation("DescribeOrganizationalUnit", %{"OrganizationalUnitId" => ou_id}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Renames an Organizational Unit.

  ## Arguments

    * `ou_id` - The OU ID.
    * `name` - The new name.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.Organizations.update_organizational_unit("ou-exam-awsccdev", "Production")
      #=> {:ok,
      #=>  %{
      #=>    organizational_unit: %{
      #=>      id: "ou-exam-awsccdev",
      #=>      arn: "arn:aws:organizations::123456789012:ou/o-exampleorgid/ou-exam-awsccdev",
      #=>      name: "Production"
      #=>    }
      #=>  }}
  """
  @spec update_organizational_unit(
          ou_id :: String.t(),
          name :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{organizational_unit: map()}} | {:error, term()}
  def update_organizational_unit(ou_id, name, opts \\ [])
      when is_binary(ou_id) and is_binary(name) do
    if sandbox?(opts) do
      sandbox_update_organizational_unit_response(ou_id, opts)
    else
      do_update_organizational_unit(ou_id, name, opts)
    end
  end

  defp do_update_organizational_unit(ou_id, name, opts) do
    data = %{"OrganizationalUnitId" => ou_id, "Name" => name}

    with {:ok, op} <- build_operation("UpdateOrganizationalUnit", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Disables trusted access for an AWS service in the organization.

  ## Arguments

    * `service_principal` - The AWS service principal to disable (e.g. `"sso.amazonaws.com"`).
    * `opts` - Shared options.

  ## Examples

      AwsSDK.Organizations.disable_aws_service_access("sso.amazonaws.com")
      #=> {:ok, %{}}
  """
  @spec disable_aws_service_access(service_principal :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def disable_aws_service_access(service_principal, opts \\ [])
      when is_binary(service_principal) do
    if sandbox?(opts) do
      sandbox_disable_aws_service_access_response(service_principal, opts)
    else
      do_disable_aws_service_access(service_principal, opts)
    end
  end

  defp do_disable_aws_service_access(service_principal, opts) do
    with {:ok, op} <-
           build_operation(
             "DisableAWSServiceAccess",
             %{"ServicePrincipal" => service_principal},
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deregisters a delegated administrator for a service.

  ## Arguments

    * `account_id` - The 12-digit account ID to deregister.
    * `service_principal` - The AWS service principal.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.Organizations.deregister_delegated_administrator(
        "333333333333",
        "sso.amazonaws.com"
      )
      #=> {:ok, %{}}
  """
  @spec deregister_delegated_administrator(
          account_id :: String.t(),
          service_principal :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{}} | {:error, term()}
  def deregister_delegated_administrator(account_id, service_principal, opts \\ [])
      when is_binary(account_id) and is_binary(service_principal) do
    if sandbox?(opts) do
      sandbox_deregister_delegated_administrator_response(account_id, opts)
    else
      do_deregister_delegated_administrator(account_id, service_principal, opts)
    end
  end

  defp do_deregister_delegated_administrator(account_id, service_principal, opts) do
    data = %{"AccountId" => account_id, "ServicePrincipal" => service_principal}

    with {:ok, op} <- build_operation("DeregisterDelegatedAdministrator", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists the direct children of a root or OU.

  ## Arguments

    * `parent_id` - The root or OU ID.
    * `child_type` - Either `"ACCOUNT"` or `"ORGANIZATIONAL_UNIT"`.
    * `opts` - Options including `:next_token`, `:max_results`, plus shared options.

  Returns `{:ok, %{children: [map()], next_token: String.t() | nil}}` where
  each child has `:id` and `:type`.

  ## Examples

      AwsSDK.Organizations.list_children("r-exam", "ORGANIZATIONAL_UNIT")
      #=> {:ok,
      #=>  %{
      #=>    children: [%{id: "ou-exam-awsccdev", type: "ORGANIZATIONAL_UNIT"}],
      #=>    next_token: nil
      #=>  }}

      AwsSDK.Organizations.list_children("ou-exam-awsccdev", "ACCOUNT")
      #=> {:ok,
      #=>  %{
      #=>    children: [%{id: "333333333333", type: "ACCOUNT"}],
      #=>    next_token: nil
      #=>  }}

  IDs and types only; call `describe_account/2` for an account's details.
  """
  @spec list_children(
          parent_id :: String.t(),
          child_type :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{children: list(map()), next_token: String.t() | nil}} | {:error, term()}
  def list_children(parent_id, child_type, opts \\ [])
      when is_binary(parent_id) and is_binary(child_type) do
    if sandbox?(opts) do
      sandbox_list_children_response(parent_id, opts)
    else
      do_list_children(parent_id, child_type, opts)
    end
  end

  defp do_list_children(parent_id, child_type, opts) do
    data =
      %{"ParentId" => parent_id, "ChildType" => child_type}
      |> maybe_put("NextToken", opts[:next_token])
      |> maybe_put("MaxResults", opts[:max_results])

    with {:ok, op} <- build_operation("ListChildren", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Sandbox delegation
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @doc false
  def build_operation(action, data, opts) do
    # Organizations is global: one endpoint per partition. `put_new` only
    # supplied a default, so an explicit `region:` -- or, more commonly, a
    # `profile:` whose config carries one -- produced
    # `organizations.<that-region>.amazonaws.com`, which does not resolve.
    # The region is fixed here for both the host and the SigV4 scope.
    opts = Keyword.put(opts, :region, global_region(opts[:region]))

    with {:ok, config} <-
           Client.resolve_config(
             :organizations,
             opts,
             &"organizations.#{&1}.amazonaws.com"
           ) do
      op = %Operation{
        method: :post,
        url: Client.simple_url(config),
        headers: [
          {"content-type", @content_type},
          {"x-amz-target", "#{@target_prefix}.#{action}"}
        ],
        body: encode_body(data),
        service: @service,
        region: config.region,
        access_key_id: config.access_key_id,
        secret_access_key: config.secret_access_key,
        security_token: config.security_token,
        http: Keyword.get(opts, :http, [])
      }

      {:ok, apply_overrides(op, opts[:organizations] || [])}
    end
  end

  defp encode_body(data) when map_size(data) === 0, do: "{}"
  defp encode_body(data), do: data |> :json.encode() |> IO.iodata_to_binary()

  defp decode_body(""), do: %{}

  defp decode_body(binary) when is_binary(binary) do
    :json.decode(binary)
  rescue
    _ -> binary
  end

  # AWS owns the response-body namespace and adds new fields over time.
  # `Serializer.deserialize/2`'s default is `to_existing_atom: true, strict: true`,
  # which crashes on any field whose snake-cased atom hasn't been referenced
  # elsewhere in the project. Bodies must round-trip without crashing, so
  # atom-safety is relaxed here by default. Callers can still override any of
  # these options by passing their own `opts` -- caller-supplied keys win the merge.
  @deserialize_defaults [to_existing_atom: false, strict: false]

  defp deserialize_opts(opts), do: Keyword.merge(@deserialize_defaults, opts)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # ---------------------------------------------------------------------------
  # Sandbox delegation
  # ---------------------------------------------------------------------------

  defp sandbox?(opts) do
    sandbox_opts = opts[:sandbox] || []
    cfg = AwsSDK.Config.sandbox()
    enabled = Keyword.get(sandbox_opts, :enabled, cfg[:enabled])

    enabled and not sandbox_disabled?()
  end

  if Code.ensure_loaded?(SandboxRegistry) do
    @doc false
    defdelegate sandbox_disabled?, to: AwsSDK.Organizations.Sandbox

    # Organization
    @doc false
    defdelegate sandbox_create_organization_response(opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :create_organization_response

    @doc false
    defdelegate sandbox_delete_organization_response(opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :delete_organization_response

    @doc false
    defdelegate sandbox_describe_organization_response(opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :describe_organization_response

    # Organizational Units
    @doc false
    defdelegate sandbox_create_organizational_unit_response(name, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :create_organizational_unit_response

    @doc false
    defdelegate sandbox_delete_organizational_unit_response(ou_id, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :delete_organizational_unit_response

    @doc false
    defdelegate sandbox_list_organizational_units_for_parent_response(parent_id, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :list_organizational_units_for_parent_response

    # Accounts
    @doc false
    defdelegate sandbox_create_account_response(name, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :create_account_response

    @doc false
    defdelegate sandbox_describe_create_account_status_response(request_id, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :describe_create_account_status_response

    @doc false
    defdelegate sandbox_move_account_response(account_id, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :move_account_response

    @doc false
    defdelegate sandbox_close_account_response(account_id, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :close_account_response

    @doc false
    defdelegate sandbox_list_accounts_response(opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :list_accounts_response

    # Roots
    @doc false
    defdelegate sandbox_list_roots_response(opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :list_roots_response

    # Delegated administrators / service access
    @doc false
    defdelegate sandbox_register_delegated_administrator_response(account_id, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :register_delegated_administrator_response

    @doc false
    defdelegate sandbox_enable_aws_service_access_response(service_principal, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :enable_aws_service_access_response

    @doc false
    defdelegate sandbox_list_delegated_administrators_response(opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :list_delegated_administrators_response

    @doc false
    defdelegate sandbox_list_aws_service_access_for_organization_response(opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :list_aws_service_access_for_organization_response

    @doc false
    defdelegate sandbox_list_parents_response(child_id, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :list_parents_response

    # Describe / update
    @doc false
    defdelegate sandbox_describe_account_response(account_id, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :describe_account_response

    @doc false
    defdelegate sandbox_describe_organizational_unit_response(ou_id, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :describe_organizational_unit_response

    @doc false
    defdelegate sandbox_update_organizational_unit_response(ou_id, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :update_organizational_unit_response

    @doc false
    defdelegate sandbox_disable_aws_service_access_response(service_principal, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :disable_aws_service_access_response

    @doc false
    defdelegate sandbox_deregister_delegated_administrator_response(account_id, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :deregister_delegated_administrator_response

    @doc false
    defdelegate sandbox_list_children_response(parent_id, opts),
      to: AwsSDK.Organizations.Sandbox,
      as: :list_children_response
  else
    defp sandbox_disabled?, do: true

    defp sandbox_create_organization_response(_), do: raise("sandbox not available")
    defp sandbox_delete_organization_response(_), do: raise("sandbox not available")
    defp sandbox_describe_organization_response(_), do: raise("sandbox not available")
    defp sandbox_create_organizational_unit_response(_, _), do: raise("sandbox not available")
    defp sandbox_delete_organizational_unit_response(_, _), do: raise("sandbox not available")

    defp sandbox_list_organizational_units_for_parent_response(_, _),
      do: raise("sandbox not available")

    defp sandbox_create_account_response(_, _), do: raise("sandbox not available")
    defp sandbox_describe_create_account_status_response(_, _), do: raise("sandbox not available")
    defp sandbox_move_account_response(_, _), do: raise("sandbox not available")
    defp sandbox_close_account_response(_, _), do: raise("sandbox not available")
    defp sandbox_list_accounts_response(_), do: raise("sandbox not available")
    defp sandbox_list_roots_response(_), do: raise("sandbox not available")

    defp sandbox_register_delegated_administrator_response(_, _),
      do: raise("sandbox not available")

    defp sandbox_enable_aws_service_access_response(_, _), do: raise("sandbox not available")
    defp sandbox_list_delegated_administrators_response(_), do: raise("sandbox not available")

    defp sandbox_list_aws_service_access_for_organization_response(_),
      do: raise("sandbox not available")

    defp sandbox_list_parents_response(_, _), do: raise("sandbox not available")
    defp sandbox_describe_account_response(_, _), do: raise("sandbox not available")
    defp sandbox_describe_organizational_unit_response(_, _), do: raise("sandbox not available")
    defp sandbox_update_organizational_unit_response(_, _), do: raise("sandbox not available")
    defp sandbox_disable_aws_service_access_response(_, _), do: raise("sandbox not available")

    defp sandbox_deregister_delegated_administrator_response(_, _),
      do: raise("sandbox not available")

    defp sandbox_list_children_response(_, _), do: raise("sandbox not available")
  end

  # ---------------------------------------------------------------------------
  # Overrides / response handling
  # ---------------------------------------------------------------------------

  @override_keys [:headers, :body, :http, :url]

  defp apply_overrides(op, overrides) do
    Enum.reduce(@override_keys, op, fn key, acc ->
      case Keyword.fetch(overrides, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  # One global endpoint per partition. A caller in GovCloud must still reach
  # the GovCloud endpoint, so the partition is honoured while the region
  # within it is fixed.
  defp global_region("us-gov-" <> _), do: "us-gov-west-1"
  defp global_region(_region), do: @default_region
end
