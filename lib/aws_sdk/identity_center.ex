defmodule AwsSDK.IdentityCenter do
  @moduledoc """
  `AwsSDK.IdentityCenter` provides an API for AWS IAM Identity Center (formerly AWS SSO).

  This module covers two underlying AWS services:

    - **`sso-admin`** — Permission sets and account assignments. Operations in this
      service require an Identity Center instance ARN, available via `list_instances/1`.

    - **`identitystore`** — Users and groups within the Identity Center identity store.
      Operations in this service require an Identity Store ID (the `identity_store_id`
      from `list_instances/1`).

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

  The following options are also available:

    - `:identity_center` - A keyword list of Identity Center endpoint
      overrides. Supported keys: `:scheme`, `:host`, `:port`. Credentials
      are not read from this sub-list; use the top-level keys above.

    - `:sandbox` - A keyword list to override sandbox configuration.
        - `:enabled` - Whether sandbox mode is enabled.
        - `:scheme` - The sandbox scheme.
        - `:host` - The sandbox host.
        - `:port` - The sandbox port.

  ## Sandbox

  Set `sandbox: [enabled: true]` to activate sandbox mode.

  ### Setup

  Add the following to your `test_helper.exs`:

      AwsSDK.IdentityCenter.Sandbox.start_link()

  ### Usage

      setup do
        AwsSDK.IdentityCenter.Sandbox.set_list_instances_responses([
          fn -> {:ok, %{instances: [%{instance_arn: "arn:aws:sso:::instance/ssoins-1", identity_store_id: "d-123"}]}} end
        ])
      end

      test "lists instances" do
        assert {:ok, %{instances: [%{instance_arn: _}]}} =
                 AwsSDK.IdentityCenter.list_instances(sandbox: [enabled: true])
      end
  """

  alias AwsSDK.Client
  alias AwsSDK.Operation
  alias ExUtils.Serializer

  @content_type "application/x-amz-json-1.1"

  @sso_service "sso"
  @sso_target_prefix "SWBExternalService"

  @identitystore_service "identitystore"
  @identitystore_target_prefix "AWSIdentityStore"

  # ---------------------------------------------------------------------------
  # Instances (sso-admin)
  # ---------------------------------------------------------------------------

  @doc """
  Lists the IAM Identity Center instances accessible in the current AWS account.

  Returns instance ARNs and identity store IDs needed for other operations.

  ## Examples

      AwsSDK.IdentityCenter.list_instances()
      #=> {:ok,
      #=>  %{
      #=>    instances: [
      #=>      %{
      #=>        instance_arn: "arn:aws:sso:::instance/ssoins-1234567890abcdef",
      #=>        identity_store_id: "d-1234567890",
      #=>        owner_account_id: "123456789012",
      #=>        status: "ACTIVE"
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}

  Both the instance ARN and the identity store ID are needed by the other
  operations in this module.
  """
  @spec list_instances(opts :: keyword()) :: {:ok, map()} | {:error, term()}
  def list_instances(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_instances_response(opts)
    else
      do_list_instances(opts)
    end
  end

  defp do_list_instances(opts) do
    with {:ok, op} <- build_operation(:sso, "ListInstances", %{}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Permission Sets (sso-admin)
  # ---------------------------------------------------------------------------

  @doc """
  Creates a permission set in the specified Identity Center instance.

  ## Arguments

    * `instance_arn` - The ARN of the Identity Center instance.
    * `name` - The permission set name.
    * `opts` - Options including `:description`, `:session_duration` (ISO 8601, e.g. `"PT8H"`),
      `:relay_state`, plus shared options.

  ## Examples

      AwsSDK.IdentityCenter.create_permission_set("arn:aws:sso:::instance/ssoins-1234567890abcdef", "AdminAccess",
        description: "Full admin",
        session_duration: "PT8H"
      )
      #=> {:ok,
      #=>  %{
      #=>    permission_set: %{
      #=>      name: "AdminAccess",
      #=>      permission_set_arn: "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef",
      #=>      description: "Full admin",
      #=>      session_duration: "PT8H",
      #=>      created_date: 1.7e9
      #=>    }
      #=>  }}

  `:session_duration` is an ISO 8601 duration.
  """
  @spec create_permission_set(instance_arn :: String.t(), name :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def create_permission_set(instance_arn, name, opts \\ [])
      when is_binary(instance_arn) and is_binary(name) do
    if sandbox?(opts) do
      sandbox_create_permission_set_response(name, opts)
    else
      do_create_permission_set(instance_arn, name, opts)
    end
  end

  defp do_create_permission_set(instance_arn, name, opts) do
    data =
      %{"InstanceArn" => instance_arn, "Name" => name}
      |> maybe_put("Description", opts[:description])
      |> maybe_put("SessionDuration", opts[:session_duration])
      |> maybe_put("RelayState", opts[:relay_state])

    with {:ok, op} <- build_operation(:sso, "CreatePermissionSet", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deletes a permission set.

  ## Arguments

    * `instance_arn` - The ARN of the Identity Center instance.
    * `permission_set_arn` - The ARN of the permission set.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IdentityCenter.delete_permission_set("arn:aws:sso:::instance/ssoins-1234567890abcdef", "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef")
      #=> {:ok, %{}}
  """
  @spec delete_permission_set(
          instance_arn :: String.t(),
          permission_set_arn :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def delete_permission_set(instance_arn, permission_set_arn, opts \\ [])
      when is_binary(instance_arn) and is_binary(permission_set_arn) do
    if sandbox?(opts) do
      sandbox_delete_permission_set_response(permission_set_arn, opts)
    else
      do_delete_permission_set(instance_arn, permission_set_arn, opts)
    end
  end

  defp do_delete_permission_set(instance_arn, permission_set_arn, opts) do
    with {:ok, op} <-
           build_operation(
             :sso,
             "DeletePermissionSet",
             %{
               "InstanceArn" => instance_arn,
               "PermissionSetArn" => permission_set_arn
             },
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists permission sets in an Identity Center instance.

  ## Arguments

    * `instance_arn` - The ARN of the Identity Center instance.
    * `opts` - Options including `:max_results`, `:next_token`, plus shared options.

  ## Examples

      AwsSDK.IdentityCenter.list_permission_sets("arn:aws:sso:::instance/ssoins-1234567890abcdef")
      #=> {:ok,
      #=>  %{
      #=>    permission_sets: [
      #=>      "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef"
      #=>    ],
      #=>    next_token: nil
      #=>  }}

  ARNs only; call `describe_permission_set/3` for the details.
  """
  @spec list_permission_sets(instance_arn :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def list_permission_sets(instance_arn, opts \\ []) when is_binary(instance_arn) do
    if sandbox?(opts) do
      sandbox_list_permission_sets_response(instance_arn, opts)
    else
      do_list_permission_sets(instance_arn, opts)
    end
  end

  defp do_list_permission_sets(instance_arn, opts) do
    data =
      %{"InstanceArn" => instance_arn}
      |> maybe_put("MaxResults", opts[:max_results])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <- build_operation(:sso, "ListPermissionSets", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Attaches an AWS managed policy to a permission set.

  ## Arguments

    * `instance_arn` - The ARN of the Identity Center instance.
    * `permission_set_arn` - The ARN of the permission set.
    * `managed_policy_arn` - The ARN of the managed policy to attach.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IdentityCenter.attach_managed_policy_to_permission_set(
        "arn:aws:sso:::instance/ssoins-1234567890abcdef",
        "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef",
        "arn:aws:iam::aws:policy/ReadOnlyAccess"
      )
      #=> {:ok, %{}}

  Call `provision_permission_set/3` afterwards to push the change to the
  accounts the permission set is assigned to.
  """
  @spec attach_managed_policy_to_permission_set(
          instance_arn :: String.t(),
          permission_set_arn :: String.t(),
          managed_policy_arn :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{}} | {:error, term()}
  def attach_managed_policy_to_permission_set(
        instance_arn,
        permission_set_arn,
        managed_policy_arn,
        opts \\ []
      )
      when is_binary(instance_arn) and is_binary(permission_set_arn) and
             is_binary(managed_policy_arn) do
    if sandbox?(opts) do
      sandbox_attach_managed_policy_to_permission_set_response(permission_set_arn, opts)
    else
      do_attach_managed_policy_to_permission_set(
        instance_arn,
        permission_set_arn,
        managed_policy_arn,
        opts
      )
    end
  end

  defp do_attach_managed_policy_to_permission_set(
         instance_arn,
         permission_set_arn,
         managed_policy_arn,
         opts
       ) do
    with {:ok, op} <-
           build_operation(
             :sso,
             "AttachManagedPolicyToPermissionSet",
             %{
               "InstanceArn" => instance_arn,
               "PermissionSetArn" => permission_set_arn,
               "ManagedPolicyArn" => managed_policy_arn
             },
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Describes a single permission set.

  ## Arguments

    * `instance_arn` - The ARN of the Identity Center instance.
    * `permission_set_arn` - The ARN of the permission set.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IdentityCenter.describe_permission_set("arn:aws:sso:::instance/ssoins-1234567890abcdef", "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef")
      #=> {:ok,
      #=>  %{
      #=>    permission_set: %{
      #=>      name: "AdminAccess",
      #=>      permission_set_arn: "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef",
      #=>      description: "Full admin",
      #=>      session_duration: "PT8H",
      #=>      relay_state: "",
      #=>      created_date: 1.7e9
      #=>    }
      #=>  }}
  """
  @spec describe_permission_set(
          instance_arn :: String.t(),
          permission_set_arn :: String.t(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def describe_permission_set(instance_arn, permission_set_arn, opts \\ [])
      when is_binary(instance_arn) and is_binary(permission_set_arn) do
    if sandbox?(opts) do
      sandbox_describe_permission_set_response(instance_arn, permission_set_arn, opts)
    else
      do_describe_permission_set(instance_arn, permission_set_arn, opts)
    end
  end

  defp do_describe_permission_set(instance_arn, permission_set_arn, opts) do
    with {:ok, op} <-
           build_operation(
             :sso,
             "DescribePermissionSet",
             %{
               "InstanceArn" => instance_arn,
               "PermissionSetArn" => permission_set_arn
             },
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Returns the inline policy document attached to a permission set.

  ## Arguments

    * `instance_arn` - The ARN of the Identity Center instance.
    * `permission_set_arn` - The ARN of the permission set.
    * `opts` - Shared options.

  Returns AWS's `GetInlinePolicyForPermissionSet` response, with
  `:inline_policy` decoded from the JSON string AWS sends it as. `nil` when
  no inline policy is attached.

  ## Examples

      AwsSDK.IdentityCenter.get_inline_policy_for_permission_set("arn:aws:sso:::instance/ssoins-1234567890abcdef", "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef")
      #=> {:ok,
      #=>  %{
      #=>    inline_policy: %{
      #=>      "Version" => "2012-10-17",
      #=>      "Statement" => [
      #=>        %{
      #=>          "Effect" => "Allow",
      #=>          "Action" => "s3:GetObject",
      #=>          "Resource" => "arn:aws:s3:::bucket/*"
      #=>        }
      #=>      ]
      #=>    }
      #=>  }}

      # No inline policy attached.
      #=> {:ok, %{inline_policy: nil}}

  AWS sends the document as a JSON string; it is decoded here. Every other
  member of the response is returned untouched.
  """
  @spec get_inline_policy_for_permission_set(
          instance_arn :: String.t(),
          permission_set_arn :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{inline_policy: map() | nil}} | {:error, term()}
  def get_inline_policy_for_permission_set(instance_arn, permission_set_arn, opts \\ [])
      when is_binary(instance_arn) and is_binary(permission_set_arn) do
    if sandbox?(opts) do
      sandbox_get_inline_policy_for_permission_set_response(
        instance_arn,
        permission_set_arn,
        opts
      )
    else
      do_get_inline_policy_for_permission_set(instance_arn, permission_set_arn, opts)
    end
  end

  defp do_get_inline_policy_for_permission_set(instance_arn, permission_set_arn, opts) do
    with {:ok, op} <-
           build_operation(
             :sso,
             "GetInlinePolicyForPermissionSet",
             %{
               "InstanceArn" => instance_arn,
               "PermissionSetArn" => permission_set_arn
             },
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      result = Serializer.deserialize(decode_body(body), deserialize_opts(opts))

      # Decoding the policy is leaf-value decoding, not reshaping: AWS sends
      # the document as a JSON string inside a JSON response. Every other key
      # in the response is left alone.
      decoded =
        case result[:inline_policy] do
          nil -> nil
          "" -> nil
          json when is_binary(json) -> :json.decode(json)
        end

      {:ok, Map.put(result, :inline_policy, decoded)}
    end
  end

  @doc """
  Lists the AWS managed policies attached to a permission set.

  ## Arguments

    * `instance_arn` - The ARN of the Identity Center instance.
    * `permission_set_arn` - The ARN of the permission set.
    * `opts` - Options including `:max_results`, `:next_token`, plus shared options.

  Returns AWS's response unchanged: `:attached_managed_policies` plus
  `:next_token`, where each attached policy has
  `:arn` and `:name`.

  ## Examples

      AwsSDK.IdentityCenter.list_managed_policies_in_permission_set("arn:aws:sso:::instance/ssoins-1234567890abcdef", "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef")
      #=> {:ok,
      #=>  %{
      #=>    attached_managed_policies: [
      #=>      %{name: "ReadOnlyAccess", arn: "arn:aws:iam::aws:policy/ReadOnlyAccess"}
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec list_managed_policies_in_permission_set(
          instance_arn :: String.t(),
          permission_set_arn :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{attached_managed_policies: list(map())}} | {:error, term()}
  def list_managed_policies_in_permission_set(instance_arn, permission_set_arn, opts \\ [])
      when is_binary(instance_arn) and is_binary(permission_set_arn) do
    if sandbox?(opts) do
      sandbox_list_managed_policies_in_permission_set_response(
        instance_arn,
        permission_set_arn,
        opts
      )
    else
      do_list_managed_policies_in_permission_set(instance_arn, permission_set_arn, opts)
    end
  end

  defp do_list_managed_policies_in_permission_set(instance_arn, permission_set_arn, opts) do
    data =
      %{"InstanceArn" => instance_arn, "PermissionSetArn" => permission_set_arn}
      |> maybe_put("MaxResults", opts[:max_results])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <- build_operation(:sso, "ListManagedPoliciesInPermissionSet", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists the principals (users or groups) assigned to a permission set for a
  given AWS account.

  ## Arguments

    * `instance_arn` - The ARN of the Identity Center instance.
    * `account_id` - The AWS account ID (the assignment target).
    * `permission_set_arn` - The ARN of the permission set.
    * `opts` - Options including `:max_results`, `:next_token`, plus shared options.

  Returns AWS's response unchanged: `:account_assignments` plus
  `:next_token`, where each assignment has
  `:account_id`, `:permission_set_arn`, `:principal_id`, `:principal_type`.

  ## Examples

      AwsSDK.IdentityCenter.list_account_assignments("arn:aws:sso:::instance/ssoins-1234567890abcdef", "333333333333", "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef")
      #=> {:ok,
      #=>  %{
      #=>    account_assignments: [
      #=>      %{
      #=>        account_id: "333333333333",
      #=>        permission_set_arn: "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef",
      #=>        principal_type: "GROUP",
      #=>        principal_id: "9067b2e8-4051-7096-b1e0-EXAMPLE"
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec list_account_assignments(
          instance_arn :: String.t(),
          account_id :: String.t(),
          permission_set_arn :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{account_assignments: list(map())}} | {:error, term()}
  def list_account_assignments(instance_arn, account_id, permission_set_arn, opts \\ [])
      when is_binary(instance_arn) and is_binary(account_id) and is_binary(permission_set_arn) do
    if sandbox?(opts) do
      sandbox_list_account_assignments_response(
        instance_arn,
        account_id,
        permission_set_arn,
        opts
      )
    else
      do_list_account_assignments(instance_arn, account_id, permission_set_arn, opts)
    end
  end

  defp do_list_account_assignments(instance_arn, account_id, permission_set_arn, opts) do
    data =
      %{
        "InstanceArn" => instance_arn,
        "AccountId" => account_id,
        "PermissionSetArn" => permission_set_arn
      }
      |> maybe_put("MaxResults", opts[:max_results])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <- build_operation(:sso, "ListAccountAssignments", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists the AWS account IDs to which a permission set is provisioned.

  ## Arguments

    * `instance_arn` - The ARN of the Identity Center instance.
    * `permission_set_arn` - The ARN of the permission set.
    * `opts` - Options including `:max_results`, `:next_token`, plus shared options.

  ## Examples

      AwsSDK.IdentityCenter.list_accounts_for_provisioned_permission_set("arn:aws:sso:::instance/ssoins-1234567890abcdef", "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef")
      #=> {:ok, %{account_ids: ["333333333333", "444444444444"], next_token: nil}}
  """
  @spec list_accounts_for_provisioned_permission_set(
          instance_arn :: String.t(),
          permission_set_arn :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{account_ids: [String.t()]}} | {:error, term()}
  def list_accounts_for_provisioned_permission_set(instance_arn, permission_set_arn, opts \\ [])
      when is_binary(instance_arn) and is_binary(permission_set_arn) do
    if sandbox?(opts) do
      sandbox_list_accounts_for_provisioned_permission_set_response(
        instance_arn,
        permission_set_arn,
        opts
      )
    else
      do_list_accounts_for_provisioned_permission_set(instance_arn, permission_set_arn, opts)
    end
  end

  defp do_list_accounts_for_provisioned_permission_set(instance_arn, permission_set_arn, opts) do
    data =
      %{"InstanceArn" => instance_arn, "PermissionSetArn" => permission_set_arn}
      |> maybe_put("MaxResults", opts[:max_results])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <-
           build_operation(:sso, "ListAccountsForProvisionedPermissionSet", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Attaches an inline policy document to a permission set.

  ## Arguments

    * `instance_arn` - The ARN of the Identity Center instance.
    * `permission_set_arn` - The ARN of the permission set.
    * `policy` - The policy document as a map (will be JSON-encoded).
    * `opts` - Shared options.

  ## Examples

      policy = %{
        "Version" => "2012-10-17",
        "Statement" => [
          %{"Effect" => "Allow", "Action" => "s3:GetObject", "Resource" => "arn:aws:s3:::bucket/*"}
        ]
      }

      AwsSDK.IdentityCenter.put_inline_policy_to_permission_set("arn:aws:sso:::instance/ssoins-1234567890abcdef", "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef", policy)
      #=> {:ok, %{}}

  Replaces any existing inline policy outright. Re-provision afterwards.
  """
  @spec put_inline_policy_to_permission_set(
          instance_arn :: String.t(),
          permission_set_arn :: String.t(),
          policy :: map(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def put_inline_policy_to_permission_set(instance_arn, permission_set_arn, policy, opts \\ [])
      when is_binary(instance_arn) and is_binary(permission_set_arn) and is_map(policy) do
    if sandbox?(opts) do
      sandbox_put_inline_policy_to_permission_set_response(
        instance_arn,
        permission_set_arn,
        policy,
        opts
      )
    else
      do_put_inline_policy_to_permission_set(instance_arn, permission_set_arn, policy, opts)
    end
  end

  defp do_put_inline_policy_to_permission_set(instance_arn, permission_set_arn, policy, opts) do
    with {:ok, op} <-
           build_operation(
             :sso,
             "PutInlinePolicyToPermissionSet",
             %{
               "InstanceArn" => instance_arn,
               "PermissionSetArn" => permission_set_arn,
               "InlinePolicy" => policy |> :json.encode() |> IO.iodata_to_binary()
             },
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Detaches a managed policy from a permission set.

  ## Arguments

    * `instance_arn` - The ARN of the Identity Center instance.
    * `permission_set_arn` - The ARN of the permission set.
    * `managed_policy_arn` - The ARN of the managed policy to detach.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IdentityCenter.detach_managed_policy_from_permission_set(
        "arn:aws:sso:::instance/ssoins-1234567890abcdef",
        "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef",
        "arn:aws:iam::aws:policy/ReadOnlyAccess"
      )
      #=> {:ok, %{}}
  """
  @spec detach_managed_policy_from_permission_set(
          instance_arn :: String.t(),
          permission_set_arn :: String.t(),
          managed_policy_arn :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{}} | {:error, term()}
  def detach_managed_policy_from_permission_set(
        instance_arn,
        permission_set_arn,
        managed_policy_arn,
        opts \\ []
      )
      when is_binary(instance_arn) and is_binary(permission_set_arn) and
             is_binary(managed_policy_arn) do
    if sandbox?(opts) do
      sandbox_detach_managed_policy_from_permission_set_response(permission_set_arn, opts)
    else
      do_detach_managed_policy_from_permission_set(
        instance_arn,
        permission_set_arn,
        managed_policy_arn,
        opts
      )
    end
  end

  defp do_detach_managed_policy_from_permission_set(
         instance_arn,
         permission_set_arn,
         managed_policy_arn,
         opts
       ) do
    with {:ok, op} <-
           build_operation(
             :sso,
             "DetachManagedPolicyFromPermissionSet",
             %{
               "InstanceArn" => instance_arn,
               "PermissionSetArn" => permission_set_arn,
               "ManagedPolicyArn" => managed_policy_arn
             },
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Account Assignments (sso-admin)
  # ---------------------------------------------------------------------------

  @doc """
  Creates an assignment that grants a principal access to an AWS account
  using a specified permission set.

  ## Arguments

    * `instance_arn` - The ARN of the Identity Center instance.
    * `assignment` - A map with the following keys:
        - `:target_id` - AWS account ID.
        - `:target_type` - `"AWS_ACCOUNT"`.
        - `:permission_set_arn` - The ARN of the permission set.
        - `:principal_type` - `"USER"` or `"GROUP"`.
        - `:principal_id` - The user or group ID.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IdentityCenter.create_account_assignment(
        "arn:aws:sso:::instance/ssoins-1234567890abcdef",
        "333333333333",
        "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef",
        principal_type: "GROUP",
        principal_id: "9067b2e8-4051-7096-b1e0-EXAMPLE"
      )
      #=> {:ok,
      #=>  %{
      #=>    account_assignment_creation_status: %{
      #=>      status: "IN_PROGRESS",
      #=>      request_id: "4c1b2f1a-EXAMPLE",
      #=>      target_id: "333333333333",
      #=>      target_type: "AWS_ACCOUNT",
      #=>      permission_set_arn: "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef",
      #=>      principal_type: "GROUP",
      #=>      principal_id: "9067b2e8-4051-7096-b1e0-EXAMPLE",
      #=>      created_date: 1.7e9
      #=>    }
      #=>  }}

  Assignment is asynchronous; the status describes the job, not a finished
  assignment.
  """
  @spec create_account_assignment(
          instance_arn :: String.t(),
          assignment :: map(),
          opts :: keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def create_account_assignment(instance_arn, assignment, opts \\ [])
      when is_binary(instance_arn) and is_map(assignment) do
    if sandbox?(opts) do
      sandbox_create_account_assignment_response(instance_arn, opts)
    else
      do_create_account_assignment(instance_arn, assignment, opts)
    end
  end

  defp do_create_account_assignment(instance_arn, assignment, opts) do
    data = %{
      "InstanceArn" => instance_arn,
      "TargetId" => assignment.target_id,
      "TargetType" => assignment.target_type,
      "PermissionSetArn" => assignment.permission_set_arn,
      "PrincipalType" => assignment.principal_type,
      "PrincipalId" => assignment.principal_id
    }

    with {:ok, op} <- build_operation(:sso, "CreateAccountAssignment", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deletes an account assignment.

  ## Arguments

    * `instance_arn` - The ARN of the Identity Center instance.
    * `assignment` - Same shape as in `create_account_assignment/3`.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IdentityCenter.delete_account_assignment(
        "arn:aws:sso:::instance/ssoins-1234567890abcdef",
        "333333333333",
        "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef",
        principal_type: "GROUP",
        principal_id: "9067b2e8-4051-7096-b1e0-EXAMPLE"
      )
      #=> {:ok,
      #=>  %{
      #=>    account_assignment_deletion_status: %{
      #=>      status: "IN_PROGRESS",
      #=>      request_id: "5d2c3f2b-EXAMPLE",
      #=>      target_id: "333333333333",
      #=>      target_type: "AWS_ACCOUNT"
      #=>    }
      #=>  }}
  """
  @spec delete_account_assignment(
          instance_arn :: String.t(),
          assignment :: map(),
          opts :: keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def delete_account_assignment(instance_arn, assignment, opts \\ [])
      when is_binary(instance_arn) and is_map(assignment) do
    if sandbox?(opts) do
      sandbox_delete_account_assignment_response(instance_arn, opts)
    else
      do_delete_account_assignment(instance_arn, assignment, opts)
    end
  end

  defp do_delete_account_assignment(instance_arn, assignment, opts) do
    data = %{
      "InstanceArn" => instance_arn,
      "TargetId" => assignment.target_id,
      "TargetType" => assignment.target_type,
      "PermissionSetArn" => assignment.permission_set_arn,
      "PrincipalType" => assignment.principal_type,
      "PrincipalId" => assignment.principal_id
    }

    with {:ok, op} <- build_operation(:sso, "DeleteAccountAssignment", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Provisions a permission set to one or all accounts where it is assigned.

  ## Arguments

    * `instance_arn` - The ARN of the Identity Center instance.
    * `permission_set_arn` - The ARN of the permission set.
    * `opts` - Options including `:target_type` (defaults to
      `"ALL_PROVISIONED_ACCOUNTS"`; use `"AWS_ACCOUNT"` with `:target_id`
      to provision a single account) and `:target_id` (required when
      `:target_type` is `"AWS_ACCOUNT"`), plus shared options.

  Returns AWS's `ProvisionPermissionSet` response unchanged, i.e.
  `%{permission_set_provisioning_status: map()}` describing the async job.

  ## Examples

      AwsSDK.IdentityCenter.provision_permission_set("arn:aws:sso:::instance/ssoins-1234567890abcdef", "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef",
        target_type: "ALL_PROVISIONED_ACCOUNTS"
      )
      #=> {:ok,
      #=>  %{
      #=>    permission_set_provisioning_status: %{
      #=>      status: "IN_PROGRESS",
      #=>      request_id: "6e3d4a3c-EXAMPLE",
      #=>      permission_set_arn: "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-1234567890abcdef",
      #=>      created_date: 1.7e9
      #=>    }
      #=>  }}

  Use `target_type: "AWS_ACCOUNT"` with `:target_id` to provision one
  account instead.
  """
  @spec provision_permission_set(
          instance_arn :: String.t(),
          permission_set_arn :: String.t(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def provision_permission_set(instance_arn, permission_set_arn, opts \\ [])
      when is_binary(instance_arn) and is_binary(permission_set_arn) do
    if sandbox?(opts) do
      sandbox_provision_permission_set_response(permission_set_arn, opts)
    else
      do_provision_permission_set(instance_arn, permission_set_arn, opts)
    end
  end

  defp do_provision_permission_set(instance_arn, permission_set_arn, opts) do
    data =
      %{
        "InstanceArn" => instance_arn,
        "PermissionSetArn" => permission_set_arn
      }
      # `TargetType` is required by AWS. Sending it only when the caller
      # supplied one made the documented two-argument call fail with a
      # ValidationException.
      |> Map.put("TargetType", opts[:target_type] || "ALL_PROVISIONED_ACCOUNTS")
      |> maybe_put("TargetId", opts[:target_id])

    with {:ok, op} <- build_operation(:sso, "ProvisionPermissionSet", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Identity Store — Users (identitystore)
  # ---------------------------------------------------------------------------

  @doc """
  Creates a user in the Identity Center identity store.

  ## Arguments

    * `identity_store_id` - The identity store ID (from `list_instances/1`).
    * `username` - The user's login name.
    * `opts` - Options including `:display_name`, `:given_name`, `:family_name`,
      `:emails` (list of `%{value: "...", type: "...", primary: true/false}`),
      plus shared options.

  ## Examples

      AwsSDK.IdentityCenter.create_identity_store_user("d-1234567890", "alice",
        display_name: "Alice Example",
        given_name: "Alice",
        family_name: "Example",
        email: "alice@example.com"
      )
      #=> {:ok, %{user_id: "9067b2e8-4051-7096-b1e0-EXAMPLEUSER", identity_store_id: "d-1234567890"}}
  """
  @spec create_identity_store_user(
          identity_store_id :: String.t(),
          username :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, %{user_id: String.t()}} | {:error, term()}
  def create_identity_store_user(identity_store_id, username, opts \\ [])
      when is_binary(identity_store_id) and is_binary(username) do
    if sandbox?(opts) do
      sandbox_create_identity_store_user_response(username, opts)
    else
      do_create_identity_store_user(identity_store_id, username, opts)
    end
  end

  defp do_create_identity_store_user(identity_store_id, username, opts) do
    data =
      %{"IdentityStoreId" => identity_store_id, "UserName" => username}
      |> maybe_put("DisplayName", opts[:display_name])
      |> maybe_put_name(opts[:given_name], opts[:family_name])
      |> maybe_put("Emails", normalize_emails(opts[:emails]))

    with {:ok, op} <- build_operation(:identitystore, "CreateUser", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deletes a user from the identity store.

  ## Arguments

    * `identity_store_id` - The identity store ID.
    * `user_id` - The user ID.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IdentityCenter.delete_identity_store_user("d-1234567890", "9067b2e8-4051-7096-b1e0-EXAMPLEUSER")
      #=> {:ok, %{}}
  """
  @spec delete_identity_store_user(
          identity_store_id :: String.t(),
          user_id :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def delete_identity_store_user(identity_store_id, user_id, opts \\ [])
      when is_binary(identity_store_id) and is_binary(user_id) do
    if sandbox?(opts) do
      sandbox_delete_identity_store_user_response(user_id, opts)
    else
      do_delete_identity_store_user(identity_store_id, user_id, opts)
    end
  end

  defp do_delete_identity_store_user(identity_store_id, user_id, opts) do
    with {:ok, op} <-
           build_operation(
             :identitystore,
             "DeleteUser",
             %{
               "IdentityStoreId" => identity_store_id,
               "UserId" => user_id
             },
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Describes a user in the identity store.

  ## Arguments

    * `identity_store_id` - The identity store ID.
    * `user_id` - The user ID.
    * `opts` - Shared options.

  Returns `{:ok, map()}` containing the user's attributes.

  ## Examples

      AwsSDK.IdentityCenter.describe_identity_store_user("d-1234567890", "9067b2e8-4051-7096-b1e0-EXAMPLEUSER")
      #=> {:ok,
      #=>  %{
      #=>    user_id: "9067b2e8-4051-7096-b1e0-EXAMPLEUSER",
      #=>    identity_store_id: "d-1234567890",
      #=>    user_name: "alice",
      #=>    display_name: "Alice Example",
      #=>    name: %{given_name: "Alice", family_name: "Example"},
      #=>    emails: [%{value: "alice@example.com", type: "work", primary: true}]
      #=>  }}
  """
  @spec describe_identity_store_user(
          identity_store_id :: String.t(),
          user_id :: String.t(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def describe_identity_store_user(identity_store_id, user_id, opts \\ [])
      when is_binary(identity_store_id) and is_binary(user_id) do
    if sandbox?(opts) do
      sandbox_describe_identity_store_user_response(user_id, opts)
    else
      do_describe_identity_store_user(identity_store_id, user_id, opts)
    end
  end

  defp do_describe_identity_store_user(identity_store_id, user_id, opts) do
    with {:ok, op} <-
           build_operation(
             :identitystore,
             "DescribeUser",
             %{"IdentityStoreId" => identity_store_id, "UserId" => user_id},
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Updates attributes of a user in the identity store.

  ## Arguments

    * `identity_store_id` - The identity store ID.
    * `user_id` - The user ID.
    * `opts` - Options specifying the attributes to update. Any of
      `:display_name`, `:given_name`, `:family_name`, and `:emails` that are
      provided are sent as `Operations` entries. Shared options are also
      accepted.

  Returns AWS's response body, which is empty for this operation.

  ## Examples

      AwsSDK.IdentityCenter.update_identity_store_user("d-1234567890", "9067b2e8-4051-7096-b1e0-EXAMPLEUSER", [
        %{attribute_path: "displayName", attribute_value: "Alice E."}
      ])
      #=> {:ok, %{}}

  Each operation targets one SCIM attribute path.
  """
  @spec update_identity_store_user(
          identity_store_id :: String.t(),
          user_id :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def update_identity_store_user(identity_store_id, user_id, opts \\ [])
      when is_binary(identity_store_id) and is_binary(user_id) do
    if sandbox?(opts) do
      sandbox_update_identity_store_user_response(user_id, opts)
    else
      do_update_identity_store_user(identity_store_id, user_id, opts)
    end
  end

  defp do_update_identity_store_user(identity_store_id, user_id, opts) do
    operations =
      []
      |> maybe_operation("displayName", opts[:display_name])
      |> maybe_operation("name.givenName", opts[:given_name])
      |> maybe_operation("name.familyName", opts[:family_name])
      |> maybe_operation("emails", normalize_emails(opts[:emails]))
      |> Enum.reverse()

    data = %{
      "IdentityStoreId" => identity_store_id,
      "UserId" => user_id,
      "Operations" => operations
    }

    with {:ok, op} <- build_operation(:identitystore, "UpdateUser", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists users in the identity store.

  ## Arguments

    * `identity_store_id` - The identity store ID.
    * `opts` - Options including `:max_results`, `:next_token`, plus shared options.

  ## Examples

      AwsSDK.IdentityCenter.list_identity_store_users("d-1234567890")
      #=> {:ok,
      #=>  %{
      #=>    users: [
      #=>      %{
      #=>        user_id: "9067b2e8-4051-7096-b1e0-EXAMPLEUSER",
      #=>        identity_store_id: "d-1234567890",
      #=>        user_name: "alice",
      #=>        display_name: "Alice Example",
      #=>        name: %{given_name: "Alice", family_name: "Example"},
      #=>        emails: [%{value: "alice@example.com", type: "work", primary: true}]
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec list_identity_store_users(identity_store_id :: String.t(), opts :: keyword()) ::
          {:ok, %{users: list(map()), next_token: String.t() | nil}} | {:error, term()}
  def list_identity_store_users(identity_store_id, opts \\ [])
      when is_binary(identity_store_id) do
    if sandbox?(opts) do
      sandbox_list_identity_store_users_response(identity_store_id, opts)
    else
      do_list_identity_store_users(identity_store_id, opts)
    end
  end

  defp do_list_identity_store_users(identity_store_id, opts) do
    data =
      %{"IdentityStoreId" => identity_store_id}
      |> maybe_put("MaxResults", opts[:max_results])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <- build_operation(:identitystore, "ListUsers", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Identity Store — Groups (identitystore)
  # ---------------------------------------------------------------------------

  @doc """
  Creates a group in the identity store.

  ## Arguments

    * `identity_store_id` - The identity store ID.
    * `display_name` - The group display name.
    * `opts` - Options including `:description`, plus shared options.

  ## Examples

      AwsSDK.IdentityCenter.create_identity_store_group("d-1234567890", "engineering",
        description: "Engineering team"
      )
      #=> {:ok, %{group_id: "a1b2c3d4-5061-7080-b1e0-EXAMPLEGRP", identity_store_id: "d-1234567890"}}
  """
  @spec create_identity_store_group(
          identity_store_id :: String.t(),
          display_name :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, %{group_id: String.t()}} | {:error, term()}
  def create_identity_store_group(identity_store_id, display_name, opts \\ [])
      when is_binary(identity_store_id) and is_binary(display_name) do
    if sandbox?(opts) do
      sandbox_create_identity_store_group_response(display_name, opts)
    else
      do_create_identity_store_group(identity_store_id, display_name, opts)
    end
  end

  defp do_create_identity_store_group(identity_store_id, display_name, opts) do
    data =
      maybe_put(
        %{"IdentityStoreId" => identity_store_id, "DisplayName" => display_name},
        "Description",
        opts[:description]
      )

    with {:ok, op} <- build_operation(:identitystore, "CreateGroup", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Deletes a group from the identity store.

  ## Arguments

    * `identity_store_id` - The identity store ID.
    * `group_id` - The group ID.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IdentityCenter.delete_identity_store_group("d-1234567890", "a1b2c3d4-5061-7080-b1e0-EXAMPLEGRP")
      #=> {:ok, %{}}
  """
  @spec delete_identity_store_group(
          identity_store_id :: String.t(),
          group_id :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def delete_identity_store_group(identity_store_id, group_id, opts \\ [])
      when is_binary(identity_store_id) and is_binary(group_id) do
    if sandbox?(opts) do
      sandbox_delete_identity_store_group_response(group_id, opts)
    else
      do_delete_identity_store_group(identity_store_id, group_id, opts)
    end
  end

  defp do_delete_identity_store_group(identity_store_id, group_id, opts) do
    with {:ok, op} <-
           build_operation(
             :identitystore,
             "DeleteGroup",
             %{
               "IdentityStoreId" => identity_store_id,
               "GroupId" => group_id
             },
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Describes a group in the identity store.

  ## Arguments

    * `identity_store_id` - The identity store ID.
    * `group_id` - The group ID.
    * `opts` - Shared options.

  Returns `{:ok, map()}` containing the group's attributes.

  ## Examples

      AwsSDK.IdentityCenter.describe_identity_store_group("d-1234567890", "a1b2c3d4-5061-7080-b1e0-EXAMPLEGRP")
      #=> {:ok,
      #=>  %{
      #=>    group_id: "a1b2c3d4-5061-7080-b1e0-EXAMPLEGRP",
      #=>    identity_store_id: "d-1234567890",
      #=>    display_name: "engineering",
      #=>    description: "Engineering team"
      #=>  }}
  """
  @spec describe_identity_store_group(
          identity_store_id :: String.t(),
          group_id :: String.t(),
          opts :: keyword()
        ) :: {:ok, map()} | {:error, term()}
  def describe_identity_store_group(identity_store_id, group_id, opts \\ [])
      when is_binary(identity_store_id) and is_binary(group_id) do
    if sandbox?(opts) do
      sandbox_describe_identity_store_group_response(group_id, opts)
    else
      do_describe_identity_store_group(identity_store_id, group_id, opts)
    end
  end

  defp do_describe_identity_store_group(identity_store_id, group_id, opts) do
    with {:ok, op} <-
           build_operation(
             :identitystore,
             "DescribeGroup",
             %{"IdentityStoreId" => identity_store_id, "GroupId" => group_id},
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Lists groups in the identity store.

  ## Arguments

    * `identity_store_id` - The identity store ID.
    * `opts` - Options including `:max_results`, `:next_token`, plus shared options.

  ## Examples

      AwsSDK.IdentityCenter.list_identity_store_groups("d-1234567890")
      #=> {:ok,
      #=>  %{
      #=>    groups: [
      #=>      %{
      #=>        group_id: "a1b2c3d4-5061-7080-b1e0-EXAMPLEGRP",
      #=>        identity_store_id: "d-1234567890",
      #=>        display_name: "engineering",
      #=>        description: "Engineering team"
      #=>      }
      #=>    ],
      #=>    next_token: nil
      #=>  }}
  """
  @spec list_identity_store_groups(identity_store_id :: String.t(), opts :: keyword()) ::
          {:ok, %{groups: list(map()), next_token: String.t() | nil}} | {:error, term()}
  def list_identity_store_groups(identity_store_id, opts \\ [])
      when is_binary(identity_store_id) do
    if sandbox?(opts) do
      sandbox_list_identity_store_groups_response(identity_store_id, opts)
    else
      do_list_identity_store_groups(identity_store_id, opts)
    end
  end

  defp do_list_identity_store_groups(identity_store_id, opts) do
    data =
      %{"IdentityStoreId" => identity_store_id}
      |> maybe_put("MaxResults", opts[:max_results])
      |> maybe_put("NextToken", opts[:next_token])

    with {:ok, op} <- build_operation(:identitystore, "ListGroups", data, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Adds a user to a group in the identity store.

  ## Arguments

    * `identity_store_id` - The identity store ID.
    * `group_id` - The group ID.
    * `user_id` - The user ID.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IdentityCenter.create_group_membership("d-1234567890", "a1b2c3d4-5061-7080-b1e0-EXAMPLEGRP", "9067b2e8-4051-7096-b1e0-EXAMPLEUSER")
      #=> {:ok,
      #=>  %{
      #=>    membership_id: "b2c3d4e5-6071-8090-c1f0-EXAMPLEMEMB",
      #=>    identity_store_id: "d-1234567890"
      #=>  }}
  """
  @spec create_group_membership(
          identity_store_id :: String.t(),
          group_id :: String.t(),
          user_id :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{membership_id: String.t()}} | {:error, term()}
  def create_group_membership(identity_store_id, group_id, user_id, opts \\ [])
      when is_binary(identity_store_id) and is_binary(group_id) and is_binary(user_id) do
    if sandbox?(opts) do
      sandbox_create_group_membership_response(group_id, opts)
    else
      do_create_group_membership(identity_store_id, group_id, user_id, opts)
    end
  end

  defp do_create_group_membership(identity_store_id, group_id, user_id, opts) do
    with {:ok, op} <-
           build_operation(
             :identitystore,
             "CreateGroupMembership",
             %{
               "IdentityStoreId" => identity_store_id,
               "GroupId" => group_id,
               "MemberId" => %{"UserId" => user_id}
             },
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  @doc """
  Removes a user from a group in the identity store.

  ## Arguments

    * `identity_store_id` - The identity store ID.
    * `membership_id` - The membership ID (from `create_group_membership/4`).
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IdentityCenter.delete_group_membership(
        "d-1234567890",
        "b2c3d4e5-6071-8090-c1f0-EXAMPLEMEMB"
      )
      #=> {:ok, %{}}

  Takes the membership ID from `create_group_membership/4`, not the user and
  group IDs.
  """
  @spec delete_group_membership(
          identity_store_id :: String.t(),
          membership_id :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def delete_group_membership(identity_store_id, membership_id, opts \\ [])
      when is_binary(identity_store_id) and is_binary(membership_id) do
    if sandbox?(opts) do
      sandbox_delete_group_membership_response(membership_id, opts)
    else
      do_delete_group_membership(identity_store_id, membership_id, opts)
    end
  end

  defp do_delete_group_membership(identity_store_id, membership_id, opts) do
    with {:ok, op} <-
           build_operation(
             :identitystore,
             "DeleteGroupMembership",
             %{
               "IdentityStoreId" => identity_store_id,
               "MembershipId" => membership_id
             },
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, Serializer.deserialize(decode_body(body), deserialize_opts(opts))}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @doc false
  def build_operation(:sso, action, data, opts) do
    build_request(
      @sso_service,
      @sso_target_prefix,
      &"sso.#{&1}.amazonaws.com",
      action,
      data,
      opts
    )
  end

  def build_operation(:identitystore, action, data, opts) do
    build_request(
      @identitystore_service,
      @identitystore_target_prefix,
      &"identitystore.#{&1}.amazonaws.com",
      action,
      data,
      opts
    )
  end

  defp build_request(service, target_prefix, default_host_fn, action, data, opts) do
    with {:ok, config} <- Client.resolve_config(:identity_center, opts, default_host_fn) do
      op = %Operation{
        method: :post,
        url: Client.simple_url(config),
        headers: [
          {"content-type", @content_type},
          {"x-amz-target", "#{target_prefix}.#{action}"}
        ],
        body: encode_body(data),
        service: service,
        region: config.region,
        access_key_id: config.access_key_id,
        secret_access_key: config.secret_access_key,
        security_token: config.security_token,
        http: Keyword.get(opts, :http, [])
      }

      {:ok, apply_overrides(op, opts[:identity_center] || [])}
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

  defp maybe_operation(ops, _path, nil), do: ops

  defp maybe_operation(ops, path, value),
    do: [%{"AttributePath" => path, "AttributeValue" => value} | ops]

  defp maybe_put_name(data, nil, nil), do: data

  defp maybe_put_name(data, given, family) do
    name =
      %{}
      |> maybe_put("GivenName", given)
      |> maybe_put("FamilyName", family)

    Map.put(data, "Name", name)
  end

  # ---------------------------------------------------------------------------
  # Sandbox delegation
  # ---------------------------------------------------------------------------

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
    defdelegate sandbox_disabled?, to: AwsSDK.IdentityCenter.Sandbox

    # Instances
    @doc false
    defdelegate sandbox_list_instances_response(opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :list_instances_response

    # Permission Sets
    @doc false
    defdelegate sandbox_create_permission_set_response(name, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :create_permission_set_response

    @doc false
    defdelegate sandbox_delete_permission_set_response(arn, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :delete_permission_set_response

    @doc false
    defdelegate sandbox_list_permission_sets_response(instance_arn, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :list_permission_sets_response

    @doc false
    defdelegate sandbox_attach_managed_policy_to_permission_set_response(ps_arn, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :attach_managed_policy_to_permission_set_response

    @doc false
    defdelegate sandbox_detach_managed_policy_from_permission_set_response(ps_arn, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :detach_managed_policy_from_permission_set_response

    # Account Assignments
    @doc false
    defdelegate sandbox_create_account_assignment_response(instance_arn, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :create_account_assignment_response

    @doc false
    defdelegate sandbox_delete_account_assignment_response(instance_arn, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :delete_account_assignment_response

    @doc false
    defdelegate sandbox_provision_permission_set_response(permission_set_arn, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :provision_permission_set_response

    # Identity Store — Users
    @doc false
    defdelegate sandbox_create_identity_store_user_response(username, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :create_identity_store_user_response

    @doc false
    defdelegate sandbox_delete_identity_store_user_response(user_id, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :delete_identity_store_user_response

    @doc false
    defdelegate sandbox_update_identity_store_user_response(user_id, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :update_identity_store_user_response

    @doc false
    defdelegate sandbox_describe_identity_store_user_response(user_id, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :describe_identity_store_user_response

    @doc false
    defdelegate sandbox_describe_identity_store_group_response(group_id, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :describe_identity_store_group_response

    @doc false
    defdelegate sandbox_list_identity_store_users_response(store_id, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :list_identity_store_users_response

    # Identity Store — Groups
    @doc false
    defdelegate sandbox_create_identity_store_group_response(name, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :create_identity_store_group_response

    @doc false
    defdelegate sandbox_delete_identity_store_group_response(group_id, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :delete_identity_store_group_response

    @doc false
    defdelegate sandbox_list_identity_store_groups_response(store_id, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :list_identity_store_groups_response

    @doc false
    defdelegate sandbox_create_group_membership_response(group_id, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :create_group_membership_response

    @doc false
    defdelegate sandbox_delete_group_membership_response(membership_id, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :delete_group_membership_response

    @doc false
    defdelegate sandbox_describe_permission_set_response(instance_arn, permission_set_arn, opts),
      to: AwsSDK.IdentityCenter.Sandbox,
      as: :describe_permission_set_response

    @doc false
    defdelegate sandbox_get_inline_policy_for_permission_set_response(
                  instance_arn,
                  permission_set_arn,
                  opts
                ),
                to: AwsSDK.IdentityCenter.Sandbox,
                as: :get_inline_policy_for_permission_set_response

    @doc false
    defdelegate sandbox_list_account_assignments_response(
                  instance_arn,
                  account_id,
                  permission_set_arn,
                  opts
                ),
                to: AwsSDK.IdentityCenter.Sandbox,
                as: :list_account_assignments_response

    @doc false
    defdelegate sandbox_list_accounts_for_provisioned_permission_set_response(
                  instance_arn,
                  permission_set_arn,
                  opts
                ),
                to: AwsSDK.IdentityCenter.Sandbox,
                as: :list_accounts_for_provisioned_permission_set_response

    @doc false
    defdelegate sandbox_list_managed_policies_in_permission_set_response(
                  instance_arn,
                  permission_set_arn,
                  opts
                ),
                to: AwsSDK.IdentityCenter.Sandbox,
                as: :list_managed_policies_in_permission_set_response

    @doc false
    defdelegate sandbox_put_inline_policy_to_permission_set_response(
                  instance_arn,
                  permission_set_arn,
                  policy,
                  opts
                ),
                to: AwsSDK.IdentityCenter.Sandbox,
                as: :put_inline_policy_to_permission_set_response
  else
    defp sandbox_disabled?, do: true

    defp sandbox_list_instances_response(_), do: raise("sandbox not available")
    defp sandbox_create_permission_set_response(_, _), do: raise("sandbox not available")
    defp sandbox_delete_permission_set_response(_, _), do: raise("sandbox not available")
    defp sandbox_list_permission_sets_response(_, _), do: raise("sandbox not available")

    defp sandbox_attach_managed_policy_to_permission_set_response(_, _),
      do: raise("sandbox not available")

    defp sandbox_detach_managed_policy_from_permission_set_response(_, _),
      do: raise("sandbox not available")

    defp sandbox_create_account_assignment_response(_, _), do: raise("sandbox not available")
    defp sandbox_delete_account_assignment_response(_, _), do: raise("sandbox not available")
    defp sandbox_create_identity_store_user_response(_, _), do: raise("sandbox not available")
    defp sandbox_delete_identity_store_user_response(_, _), do: raise("sandbox not available")
    defp sandbox_update_identity_store_user_response(_, _), do: raise("sandbox not available")
    defp sandbox_provision_permission_set_response(_, _), do: raise("sandbox not available")
    defp sandbox_describe_identity_store_user_response(_, _), do: raise("sandbox not available")
    defp sandbox_describe_identity_store_group_response(_, _), do: raise("sandbox not available")
    defp sandbox_list_identity_store_users_response(_, _), do: raise("sandbox not available")
    defp sandbox_create_identity_store_group_response(_, _), do: raise("sandbox not available")
    defp sandbox_delete_identity_store_group_response(_, _), do: raise("sandbox not available")
    defp sandbox_list_identity_store_groups_response(_, _), do: raise("sandbox not available")
    defp sandbox_create_group_membership_response(_, _), do: raise("sandbox not available")
    defp sandbox_delete_group_membership_response(_, _), do: raise("sandbox not available")

    defp sandbox_describe_permission_set_response(_instance_arn, _permission_set_arn, _opts),
      do: raise("sandbox not available")

    defp sandbox_get_inline_policy_for_permission_set_response(
           _instance_arn,
           _permission_set_arn,
           _opts
         ),
         do: raise("sandbox not available")

    defp sandbox_list_account_assignments_response(
           _instance_arn,
           _account_id,
           _permission_set_arn,
           _opts
         ),
         do: raise("sandbox not available")

    defp sandbox_list_accounts_for_provisioned_permission_set_response(
           _instance_arn,
           _permission_set_arn,
           _opts
         ),
         do: raise("sandbox not available")

    defp sandbox_list_managed_policies_in_permission_set_response(
           _instance_arn,
           _permission_set_arn,
           _opts
         ),
         do: raise("sandbox not available")

    defp sandbox_put_inline_policy_to_permission_set_response(
           _instance_arn,
           _permission_set_arn,
           _policy,
           _opts
         ),
         do: raise("sandbox not available")
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

  # The identitystore `Email` shape members are `Value`, `Type` and `Primary`.
  # Callers follow the documented `%{value:, type:, primary:}` shape, which
  # JSON-encodes to lowercase keys and is rejected with a ValidationException.
  defp normalize_emails(nil), do: nil
  defp normalize_emails(emails) when is_list(emails), do: Enum.map(emails, &normalize_email/1)
  defp normalize_emails(other), do: other

  defp normalize_email(%{} = email) do
    Map.new(email, fn {k, v} -> {email_member(k), v} end)
  end

  defp normalize_email(other), do: other

  defp email_member(key) when is_atom(key), do: key |> Atom.to_string() |> email_member()
  defp email_member("value"), do: "Value"
  defp email_member("type"), do: "Type"
  defp email_member("primary"), do: "Primary"
  defp email_member(key), do: key
end
