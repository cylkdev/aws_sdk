defmodule AwsSDK.IAM do
  @moduledoc """
  `AwsSDK.IAM` provides an API for AWS Identity and Access Management (IAM).

  This module calls the AWS IAM Query API directly via `AwsSDK.HTTP` and
  `AwsSDK.Signer` (through `AwsSDK.IAM.Client`).

  IAM's public API is XML-only at the AWS wire level. The service model
  (`botocore/data/iam/2010-05-08/service-2.json`) declares
  `metadata.protocols = ["query"]`, and AWS does not expose a JSON IAM
  endpoint. The form-urlencoded request / XML response handling here
  (XPath extraction via `SweetXml`) is a consequence of AWS's protocol
  choice, not a library decision.

  IAM is a global service; all requests are routed to `iam.amazonaws.com`
  regardless of `:region` (SigV4 still needs a region, so `us-east-1` is
  used by convention).

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

  IAM is a global service; requests always go to `iam.amazonaws.com`. The
  `:region` opt is used only for SigV4 signing and defaults to `"us-east-1"`.

  The following options are also available:

    - `:iam` - A keyword list of IAM endpoint overrides. Supported keys:
      `:scheme`, `:host`, `:port`. Credentials are not read from this
      sub-list; use the top-level keys above.

    - `:sandbox` - A keyword list to override sandbox configuration.
        - `:enabled` - Whether sandbox mode is enabled.
        - `:scheme` - The sandbox scheme.
        - `:host` - The sandbox host.
        - `:port` - The sandbox port.

  ## Sandbox

  Set `sandbox: [enabled: true]` to activate sandbox mode.

  ### Setup

  Add the following to your `test_helper.exs`:

      AwsSDK.IAM.Sandbox.start_link()

  ### Usage

      setup do
        AwsSDK.IAM.Sandbox.set_create_user_responses([
          {"alice", fn -> {:ok, %{user_name: "alice", arn: "arn:aws:iam::123:user/alice"}} end}
        ])
      end

      test "creates a user" do
        assert {:ok, %{user_name: "alice"}} =
                 AwsSDK.IAM.create_user("alice", sandbox: [enabled: true])
      end
  """

  import SweetXml, only: [xpath: 2, xpath: 3, sigil_x: 2]

  alias AwsSDK.Client
  alias AwsSDK.Operation

  @service "iam"
  @content_type "application/x-www-form-urlencoded"
  @api_version "2010-05-08"
  @default_region "us-east-1"
  @default_host "iam.amazonaws.com"

  # ---------------------------------------------------------------------------
  # Users
  # ---------------------------------------------------------------------------

  @doc """
  Creates an IAM user.

  ## Arguments

    * `username` - The user name (1–128 chars).
    * `opts` - Options including `:path` and `:permissions_boundary`, plus
      shared options. AWS's `Tags` parameter is not encoded.

  ## Examples

      AwsSDK.IAM.create_user("alice", path: "/engineering/")
      #=> {:ok,
      #=>  %{
      #=>    user: %{
      #=>      user_name: "alice",
      #=>      user_id: "AIDA1EXAMPLE",
      #=>      arn: "arn:aws:iam::123456789012:user/alice",
      #=>      path: "/",
      #=>      create_date: "2026-01-01T00:00:00Z",
      #=>      password_last_used: "",
      #=>      permissions_boundary: nil,
      #=>      tags: []
      #=>    }
      #=>  }}

  The result keeps AWS's `CreateUserResult/User` envelope, so the user sits
  under `:user`.
  """
  @spec create_user(username :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def create_user(username, opts \\ []) do
    if sandbox?(opts) do
      sandbox_create_user_response(username, opts)
    else
      do_create_user(username, opts)
    end
  end

  defp do_create_user(username, opts) do
    params =
      %{"UserName" => username}
      |> maybe_put("Path", opts[:path])
      |> maybe_put("PermissionsBoundary", opts[:permissions_boundary])

    with {:ok, op} <- build_operation("CreateUser", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, %{user: parse_user(body, ~x"//CreateUserResult/User"e)}}
    end
  end

  @doc """
  Retrieves information about an IAM user.

  ## Arguments

    * `username` - The user name.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.get_user(user_name: "alice")
      #=> {:ok,
      #=>  %{
      #=>    user: %{
      #=>      user_name: "alice",
      #=>      user_id: "AIDA1EXAMPLE",
      #=>      arn: "arn:aws:iam::123456789012:user/alice",
      #=>      path: "/",
      #=>      create_date: "2026-01-01T00:00:00Z",
      #=>      password_last_used: "2026-02-01T12:00:00Z",
      #=>      permissions_boundary: %{
      #=>        permissions_boundary_arn: "arn:aws:iam::123456789012:policy/boundary",
      #=>        permissions_boundary_type: "Policy"
      #=>      },
      #=>      tags: [%{key: "team", value: "infra"}]
      #=>    }
      #=>  }}

      # Omit :user_name to describe the caller's own user.
      AwsSDK.IAM.get_user()
      #=> {:ok, %{user: %{user_name: "alice"}}}
  """
  @spec get_user(opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def get_user(opts \\ []) do
    if sandbox?(opts) do
      sandbox_get_user_response(opts)
    else
      do_get_user(opts)
    end
  end

  defp do_get_user(opts) do
    with {:ok, op} <-
           build_operation("GetUser", maybe_put(%{}, "UserName", opts[:user_name]), opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, %{user: parse_user(body, ~x"//GetUserResult/User"e)}}
    end
  end

  @doc """
  Lists IAM users, optionally filtered by path prefix.

  ## Options

    * `:path_prefix` - Filter users whose path begins with this string.
    * `:max_items` - Maximum number of items to return.
    * `:marker` - Pagination marker from a previous call.

  ## Examples

      AwsSDK.IAM.list_users(path_prefix: "/engineering/")
      #=> {:ok,
      #=>  %{
      #=>    users: [
      #=>      %{
      #=>        user_name: "alice",
      #=>        user_id: "AIDA1EXAMPLE",
      #=>        arn: "arn:aws:iam::123456789012:user/engineering/alice",
      #=>        path: "/engineering/",
      #=>        create_date: "2026-01-01T00:00:00Z",
      #=>        permissions_boundary: nil,
      #=>        tags: []
      #=>      }
      #=>    ],
      #=>    is_truncated: false,
      #=>    marker: nil
      #=>  }}

  Each user carries the same members as `get_user/1` returns. When
  `:is_truncated` is true, pass `:marker` back to fetch the next page.
  """
  @spec list_users(opts :: keyword()) ::
          {:ok, %{users: list(map()), is_truncated: boolean(), marker: String.t() | nil}}
          | {:error, term()}
  def list_users(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_users_response(opts)
    else
      do_list_users(opts)
    end
  end

  defp do_list_users(opts) do
    params =
      %{}
      |> maybe_put("PathPrefix", opts[:path_prefix])
      |> maybe_put("MaxItems", opts[:max_items])
      |> maybe_put("Marker", opts[:marker])

    with {:ok, op} <- build_operation("ListUsers", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      marker = xpath(body, ~x"//ListUsersResult/Marker/text()"s)

      {:ok,
       %{
         users: parse_user(body, ~x"//ListUsersResult/Users/member"l),
         is_truncated: xpath(body, ~x"//ListUsersResult/IsTruncated/text()"s) === "true",
         marker: if(marker === "", do: nil, else: marker)
       }}
    end
  end

  @doc """
  Deletes an IAM user.

  ## Arguments

    * `username` - The user name.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.delete_user("alice")
      #=> {:ok, %{}}

  AWS returns an empty body. Access keys, policies and group memberships
  must be removed first or AWS rejects the call.
  """
  @spec delete_user(username :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def delete_user(username, opts \\ []) do
    if sandbox?(opts) do
      sandbox_delete_user_response(username, opts)
    else
      do_delete_user(username, opts)
    end
  end

  defp do_delete_user(username, opts) do
    with {:ok, op} <- build_operation("DeleteUser", %{"UserName" => username}, opts),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  # ---------------------------------------------------------------------------
  # Access Keys
  # ---------------------------------------------------------------------------

  @doc """
  Creates an access key pair for an IAM user.

  Returns the `secret_access_key` — this is the only time it is visible.

  ## Arguments

    * `username` - The user name.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.create_access_key(user_name: "alice")
      #=> {:ok,
      #=>  %{
      #=>    access_key: %{
      #=>      access_key_id: "AKIA1EXAMPLE",
      #=>      # The only time AWS ever returns the secret.
      #=>      secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
      #=>      user_name: "alice",
      #=>      status: "Active",
      #=>      create_date: "2026-01-01T00:00:00Z"
      #=>    }
      #=>  }}
  """
  @spec create_access_key(opts :: keyword()) ::
          {:ok, %{access_key_id: String.t(), secret_access_key: String.t()}} | {:error, term()}
  def create_access_key(opts \\ []) do
    if sandbox?(opts) do
      sandbox_create_access_key_response(opts)
    else
      do_create_access_key(opts)
    end
  end

  defp do_create_access_key(opts) do
    with {:ok, op} <-
           build_operation("CreateAccessKey", maybe_put(%{}, "UserName", opts[:user_name]), opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, %{access_key: parse_access_key(body, ~x"//CreateAccessKeyResult/AccessKey"e)}}
    end
  end

  @doc """
  Lists access keys for an IAM user.

  ## Arguments

    * `username` - The user name.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.list_access_keys(user_name: "alice")
      #=> {:ok,
      #=>  %{
      #=>    access_key_metadata: [
      #=>      %{
      #=>        access_key_id: "AKIA1EXAMPLE",
      #=>        user_name: "alice",
      #=>        status: "Active",
      #=>        create_date: "2026-01-01T00:00:00Z"
      #=>      }
      #=>    ],
      #=>    is_truncated: false,
      #=>    marker: nil
      #=>  }}

  The key is `:access_key_metadata`, which is AWS's member name; secrets are
  never returned here.
  """
  @spec list_access_keys(opts :: keyword()) ::
          {:ok,
           %{
             access_key_metadata: list(map()),
             is_truncated: boolean(),
             marker: String.t() | nil
           }}
          | {:error, term()}
  def list_access_keys(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_access_keys_response(opts)
    else
      do_list_access_keys(opts)
    end
  end

  defp do_list_access_keys(opts) do
    params =
      %{}
      |> maybe_put("UserName", opts[:user_name])
      |> maybe_put("Marker", opts[:marker])
      |> maybe_put("MaxItems", opts[:max_items])

    with {:ok, op} <- build_operation("ListAccessKeys", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      access_key_metadata =
        xpath(body, ~x"//AccessKeyMetadata/member"l,
          access_key_id: ~x"./AccessKeyId/text()"s,
          user_name: ~x"./UserName/text()"s,
          status: ~x"./Status/text()"s,
          create_date: ~x"./CreateDate/text()"s
        )

      {:ok,
       %{
         access_key_metadata: access_key_metadata,
         is_truncated: xpath(body, ~x"//ListAccessKeysResult/IsTruncated/text()"s) == "true",
         marker: xpath(body, ~x"//ListAccessKeysResult/Marker/text()"so)
       }}
    end
  end

  @doc """
  Deletes an access key.

  ## Arguments

    * `access_key_id` - The access key ID.
    * `username` - The user name.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.delete_access_key("AKIA1EXAMPLE", user_name: "alice")
      #=> {:ok, %{}}
  """
  @spec delete_access_key(access_key_id :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def delete_access_key(access_key_id, opts \\ []) when is_binary(access_key_id) do
    if sandbox?(opts) do
      sandbox_delete_access_key_response(access_key_id, opts)
    else
      do_delete_access_key(access_key_id, opts)
    end
  end

  defp do_delete_access_key(access_key_id, opts) do
    params = maybe_put(%{"AccessKeyId" => access_key_id}, "UserName", opts[:user_name])

    with {:ok, op} <- build_operation("DeleteAccessKey", params, opts),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  # ---------------------------------------------------------------------------
  # Groups
  # ---------------------------------------------------------------------------

  @doc """
  Creates an IAM group.

  ## Arguments

    * `name` - The group name.
    * `opts` - Options including `:path`, plus shared options.

  ## Examples

      AwsSDK.IAM.create_group("developers")
      #=> {:ok,
      #=>  %{
      #=>    group: %{
      #=>      group_name: "developers",
      #=>      group_id: "AGPA1EXAMPLE",
      #=>      arn: "arn:aws:iam::123456789012:group/developers",
      #=>      path: "/",
      #=>      create_date: "2026-01-01T00:00:00Z"
      #=>    }
      #=>  }}
  """
  @spec create_group(name :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def create_group(name, opts \\ []) do
    if sandbox?(opts) do
      sandbox_create_group_response(name, opts)
    else
      do_create_group(name, opts)
    end
  end

  defp do_create_group(name, opts) do
    params = maybe_put(%{"GroupName" => name}, "Path", opts[:path])

    with {:ok, op} <- build_operation("CreateGroup", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, %{group: parse_group(body, ~x"//CreateGroupResult/Group"e)}}
    end
  end

  @doc """
  Lists IAM groups.

  ## Options

    * `:path_prefix` - Filter groups whose path begins with this string.

  ## Examples

      AwsSDK.IAM.list_groups()
      #=> {:ok,
      #=>  %{
      #=>    groups: [
      #=>      %{
      #=>        group_name: "developers",
      #=>        group_id: "AGPA1EXAMPLE",
      #=>        arn: "arn:aws:iam::123456789012:group/developers",
      #=>        path: "/",
      #=>        create_date: "2026-01-01T00:00:00Z"
      #=>      }
      #=>    ],
      #=>    is_truncated: false,
      #=>    marker: nil
      #=>  }}
  """
  @spec list_groups(opts :: keyword()) ::
          {:ok, %{groups: list(map()), is_truncated: boolean(), marker: String.t() | nil}}
          | {:error, term()}
  def list_groups(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_groups_response(opts)
    else
      do_list_groups(opts)
    end
  end

  defp do_list_groups(opts) do
    params =
      %{}
      |> maybe_put("PathPrefix", opts[:path_prefix])
      |> maybe_put("MaxItems", opts[:max_items])
      |> maybe_put("Marker", opts[:marker])

    with {:ok, op} <- build_operation("ListGroups", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      groups =
        xpath(body, ~x"//Groups/member"l,
          group_name: ~x"./GroupName/text()"s,
          group_id: ~x"./GroupId/text()"s,
          arn: ~x"./Arn/text()"s,
          path: ~x"./Path/text()"s,
          create_date: ~x"./CreateDate/text()"s
        )

      {:ok,
       %{
         groups: groups,
         is_truncated: xpath(body, ~x"//ListGroupsResult/IsTruncated/text()"s) == "true",
         marker: xpath(body, ~x"//ListGroupsResult/Marker/text()"so)
       }}
    end
  end

  @doc """
  Deletes an IAM group.

  ## Arguments

    * `name` - The group name.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.delete_group("developers")
      #=> {:ok, %{}}
  """
  @spec delete_group(name :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def delete_group(name, opts \\ []) do
    if sandbox?(opts) do
      sandbox_delete_group_response(name, opts)
    else
      do_delete_group(name, opts)
    end
  end

  defp do_delete_group(name, opts) do
    with {:ok, op} <- build_operation("DeleteGroup", %{"GroupName" => name}, opts),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  # ---------------------------------------------------------------------------
  # Group membership
  # ---------------------------------------------------------------------------

  @doc """
  Adds an IAM user to a group.

  ## Arguments

    * `group_name` - The group name.
    * `username` - The user name.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.add_user_to_group("developers", "alice")
      #=> {:ok, %{}}
  """
  @spec add_user_to_group(group_name :: String.t(), username :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def add_user_to_group(group_name, username, opts \\ []) do
    if sandbox?(opts) do
      sandbox_add_user_to_group_response(group_name, username, opts)
    else
      do_add_user_to_group(group_name, username, opts)
    end
  end

  defp do_add_user_to_group(group_name, username, opts) do
    with {:ok, op} <-
           build_operation(
             "AddUserToGroup",
             %{"GroupName" => group_name, "UserName" => username},
             opts
           ),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Removes an IAM user from a group.

  ## Arguments

    * `group_name` - The group name.
    * `username` - The user name.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.remove_user_from_group("developers", "alice")
      #=> {:ok, %{}}
  """
  @spec remove_user_from_group(
          group_name :: String.t(),
          username :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, %{}} | {:error, term()}
  def remove_user_from_group(group_name, username, opts \\ []) do
    if sandbox?(opts) do
      sandbox_remove_user_from_group_response(group_name, username, opts)
    else
      do_remove_user_from_group(group_name, username, opts)
    end
  end

  defp do_remove_user_from_group(group_name, username, opts) do
    with {:ok, op} <-
           build_operation(
             "RemoveUserFromGroup",
             %{"GroupName" => group_name, "UserName" => username},
             opts
           ),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  # ---------------------------------------------------------------------------
  # Roles
  # ---------------------------------------------------------------------------

  @doc """
  Creates an IAM role with a trust policy.

  ## Arguments

    * `name` - The role name.
    * `trust_policy` - Elixir map defining the trust (assume-role) policy document.
      This is JSON-encoded before being sent to AWS.
    * `opts` - Options including `:path`, `:description`, `:max_session_duration`,
      plus shared options.

  ## Examples

      trust_policy = %{
        "Version" => "2012-10-17",
        "Statement" => [
          %{
            "Effect" => "Allow",
            "Principal" => %{"Service" => "ec2.amazonaws.com"},
            "Action" => "sts:AssumeRole"
          }
        ]
      }

      AwsSDK.IAM.create_role("AppRole", trust_policy, description: "App instance role")
      #=> {:ok,
      #=>  %{
      #=>    role: %{
      #=>      role_name: "AppRole",
      #=>      role_id: "AROA1EXAMPLE",
      #=>      arn: "arn:aws:iam::123456789012:role/AppRole",
      #=>      path: "/",
      #=>      create_date: "2026-01-01T00:00:00Z",
      #=>      description: "App instance role",
      #=>      # URL-encoded per RFC 3986, as AWS returns it.
      #=>      assume_role_policy_document: "%7B%22Version%22%3A%222012-10-17%22...",
      #=>      max_session_duration: 3600,
      #=>      permissions_boundary: nil,
      #=>      role_last_used: nil,
      #=>      tags: []
      #=>    }
      #=>  }}
  """
  @spec create_role(name :: String.t(), trust_policy :: map(), opts :: keyword()) ::
          {:ok, %{role_name: String.t(), role_id: String.t(), arn: String.t()}} | {:error, term()}
  def create_role(name, trust_policy, opts \\ []) do
    if sandbox?(opts) do
      sandbox_create_role_response(name, opts)
    else
      do_create_role(name, trust_policy, opts)
    end
  end

  defp do_create_role(name, trust_policy, opts) do
    params =
      %{
        "RoleName" => name,
        "AssumeRolePolicyDocument" => trust_policy |> :json.encode() |> IO.iodata_to_binary()
      }
      |> maybe_put("Path", opts[:path])
      |> maybe_put("Description", opts[:description])
      |> maybe_put("MaxSessionDuration", opts[:max_session_duration])

    with {:ok, op} <- build_operation("CreateRole", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, %{role: parse_role(body, ~x"//Role"e)}}
    end
  end

  @doc """
  Returns information about an IAM role.

  ## Arguments

    * `name` - The role name.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.get_role("AppRole")
      #=> {:ok,
      #=>  %{
      #=>    role: %{
      #=>      role_name: "AppRole",
      #=>      role_id: "AROA1EXAMPLE",
      #=>      arn: "arn:aws:iam::123456789012:role/AppRole",
      #=>      path: "/",
      #=>      create_date: "2026-01-01T00:00:00Z",
      #=>      description: "App instance role",
      #=>      assume_role_policy_document: "%7B%22Version%22%3A%222012-10-17%22...",
      #=>      max_session_duration: 3600,
      #=>      permissions_boundary: %{
      #=>        permissions_boundary_arn: "arn:aws:iam::123456789012:policy/boundary",
      #=>        permissions_boundary_type: "Policy"
      #=>      },
      #=>      role_last_used: %{
      #=>        last_used_date: "2026-02-01T12:00:00Z",
      #=>        region: "us-east-1"
      #=>      },
      #=>      tags: [%{key: "team", value: "infra"}]
      #=>    }
      #=>  }}

  `:permissions_boundary` and `:role_last_used` are structures on the wire
  and stay structures here; both are `nil` when AWS omits them.
  """
  @spec get_role(name :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def get_role(name, opts \\ []) do
    if sandbox?(opts) do
      sandbox_get_role_response(name, opts)
    else
      do_get_role(name, opts)
    end
  end

  defp do_get_role(name, opts) do
    with {:ok, op} <- build_operation("GetRole", %{"RoleName" => name}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, %{role: parse_role(body, ~x"//Role"e)}}
    end
  end

  # ---------------------------------------------------------------------------
  # Instance profiles
  # ---------------------------------------------------------------------------

  @doc """
  Retrieves information about the specified instance profile, including
  its creation date and the roles associated with it.

  ## Examples

      AwsSDK.IAM.get_instance_profile("web")
      #=> {:ok,
      #=>  %{
      #=>    instance_profile: %{
      #=>      path: "/",
      #=>      instance_profile_name: "web",
      #=>      instance_profile_id: "AIPAEXAMPLE",
      #=>      arn: "arn:aws:iam::123456789012:instance-profile/web",
      #=>      create_date: "2026-01-01T00:00:00Z",
      #=>      roles: [
      #=>        %{
      #=>          role_name: "web-role",
      #=>          role_id: "AROAEXAMPLE",
      #=>          arn: "arn:aws:iam::123456789012:role/web-role",
      #=>          path: "/",
      #=>          create_date: "2026-01-01T00:00:00Z"
      #=>        }
      #=>      ],
      #=>      tags: [%{key: "Team", value: "ops"}]
      #=>    }
      #=>  }}

  The nested roles carry every member `get_role/2` returns.
  """
  @spec get_instance_profile(instance_profile_name :: String.t(), opts :: keyword()) ::
          {:ok, %{instance_profile: map()}} | {:error, term()}
  def get_instance_profile(instance_profile_name, opts \\ [])
      when is_binary(instance_profile_name) do
    if sandbox?(opts) do
      sandbox_get_instance_profile_response(instance_profile_name, opts)
    else
      do_get_instance_profile(instance_profile_name, opts)
    end
  end

  defp do_get_instance_profile(instance_profile_name, opts) do
    params = %{"InstanceProfileName" => instance_profile_name}

    with {:ok, op} <- build_operation("GetInstanceProfile", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, parse_instance_profile(body)}
    end
  end

  @doc false
  def parse_instance_profile_for_test(xml), do: parse_instance_profile(xml)

  defp parse_instance_profile(body) do
    %{
      instance_profile: %{
        path: xpath(body, ~x"//GetInstanceProfileResult/InstanceProfile/Path/text()"s),
        instance_profile_name:
          xpath(body, ~x"//GetInstanceProfileResult/InstanceProfile/InstanceProfileName/text()"s),
        instance_profile_id:
          xpath(body, ~x"//GetInstanceProfileResult/InstanceProfile/InstanceProfileId/text()"s),
        arn: xpath(body, ~x"//GetInstanceProfileResult/InstanceProfile/Arn/text()"s),
        create_date:
          xpath(body, ~x"//GetInstanceProfileResult/InstanceProfile/CreateDate/text()"s),
        roles: parse_role(body, ~x"//GetInstanceProfileResult/InstanceProfile/Roles/member"l),
        tags:
          xpath(body, ~x"//GetInstanceProfileResult/InstanceProfile/Tags/member"l,
            key: ~x"./Key/text()"s,
            value: ~x"./Value/text()"s
          )
      }
    }
  end

  @doc """
  Lists IAM roles.

  ## Options

    * `:path_prefix` - Filter roles whose path begins with this string.
    * `:max_items` - Maximum number of items.
    * `:marker` - Pagination marker.

  ## Examples

      AwsSDK.IAM.list_roles(path_prefix: "/service-role/")
      #=> {:ok,
      #=>  %{
      #=>    roles: [
      #=>      %{
      #=>        role_name: "AppRole",
      #=>        role_id: "AROA1EXAMPLE",
      #=>        arn: "arn:aws:iam::123456789012:role/service-role/AppRole",
      #=>        path: "/service-role/",
      #=>        create_date: "2026-01-01T00:00:00Z",
      #=>        assume_role_policy_document: "%7B%22Version%22%3A%222012-10-17%22...",
      #=>        max_session_duration: 3600,
      #=>        permissions_boundary: nil,
      #=>        role_last_used: nil,
      #=>        tags: []
      #=>      }
      #=>    ],
      #=>    is_truncated: false,
      #=>    marker: nil
      #=>  }}

  Each role carries the same members as `get_role/2` returns.
  """
  @spec list_roles(opts :: keyword()) ::
          {:ok, %{roles: list(map()), is_truncated: boolean(), marker: String.t() | nil}}
          | {:error, term()}
  def list_roles(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_roles_response(opts)
    else
      do_list_roles(opts)
    end
  end

  defp do_list_roles(opts) do
    params =
      %{}
      |> maybe_put("PathPrefix", opts[:path_prefix])
      |> maybe_put("Marker", opts[:marker])
      |> maybe_put("MaxItems", opts[:max_items])

    with {:ok, op} <- build_operation("ListRoles", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok,
       %{
         roles: parse_role(body, ~x"//Roles/member"l),
         is_truncated: xpath(body, ~x"//ListRolesResult/IsTruncated/text()"s) == "true",
         marker: xpath(body, ~x"//ListRolesResult/Marker/text()"so)
       }}
    end
  end

  @doc """
  Deletes an IAM role.

  ## Arguments

    * `name` - The role name.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.delete_role("AppRole")
      #=> {:ok, %{}}

  Inline and attached policies must be removed first.
  """
  @spec delete_role(name :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def delete_role(name, opts \\ []) do
    if sandbox?(opts) do
      sandbox_delete_role_response(name, opts)
    else
      do_delete_role(name, opts)
    end
  end

  defp do_delete_role(name, opts) do
    with {:ok, op} <- build_operation("DeleteRole", %{"RoleName" => name}, opts),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Updates the trust policy (assume role policy document) of an IAM role.

  ## Arguments

    * `role_name` - The role name.
    * `policy_document` - Elixir map of the trust policy. JSON-encoded before sending.
    * `opts` - Shared options.

  ## Examples

      trust_policy = %{
        "Version" => "2012-10-17",
        "Statement" => [
          %{
            "Effect" => "Allow",
            "Principal" => %{"Service" => "ec2.amazonaws.com"},
            "Action" => "sts:AssumeRole"
          }
        ]
      }

      AwsSDK.IAM.update_assume_role_policy("AppRole", trust_policy)
      #=> {:ok, %{}}
  """
  @spec update_assume_role_policy(
          role_name :: String.t(),
          policy_document :: map(),
          opts :: keyword()
        ) :: {:ok, %{}} | {:error, term()}
  def update_assume_role_policy(role_name, policy_document, opts \\ []) do
    if sandbox?(opts) do
      sandbox_update_assume_role_policy_response(role_name, opts)
    else
      do_update_assume_role_policy(role_name, policy_document, opts)
    end
  end

  defp do_update_assume_role_policy(role_name, policy_document, opts) do
    params = %{
      "RoleName" => role_name,
      "PolicyDocument" => policy_document |> :json.encode() |> IO.iodata_to_binary()
    }

    with {:ok, op} <- build_operation("UpdateAssumeRolePolicy", params, opts),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  # ---------------------------------------------------------------------------
  # Inline role policies
  # ---------------------------------------------------------------------------

  @doc """
  Adds or updates an inline policy document embedded in an IAM role.

  ## Arguments

    * `role_name` - The role name.
    * `policy_name` - The inline policy name.
    * `document` - Elixir map of the policy. JSON-encoded before sending.
    * `opts` - Shared options.

  ## Examples

      policy = %{
        "Version" => "2012-10-17",
        "Statement" => [
          %{"Effect" => "Allow", "Action" => "s3:GetObject", "Resource" => "arn:aws:s3:::bucket/*"}
        ]
      }

      AwsSDK.IAM.put_role_policy("AppRole", "read-bucket", policy)
      #=> {:ok, %{}}
  """
  @spec put_role_policy(
          role_name :: String.t(),
          policy_name :: String.t(),
          document :: map(),
          opts :: keyword()
        ) :: {:ok, %{}} | {:error, term()}
  def put_role_policy(role_name, policy_name, document, opts \\ []) do
    if sandbox?(opts) do
      sandbox_put_role_policy_response(role_name, policy_name, opts)
    else
      do_put_role_policy(role_name, policy_name, document, opts)
    end
  end

  defp do_put_role_policy(role_name, policy_name, document, opts) do
    params = %{
      "RoleName" => role_name,
      "PolicyName" => policy_name,
      "PolicyDocument" => document |> :json.encode() |> IO.iodata_to_binary()
    }

    with {:ok, op} <- build_operation("PutRolePolicy", params, opts),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Returns an inline policy document embedded in an IAM role.

  The `<PolicyDocument>` element returned by AWS is URL-encoded JSON; this
  function URI-decodes and JSON-decodes it so `:policy_document` is an
  Elixir map.

  ## Arguments

    * `role_name` - The role name.
    * `policy_name` - The inline policy name.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.get_role_policy("AppRole", "read-bucket")
      #=> {:ok,
      #=>  %{
      #=>    role_name: "AppRole",
      #=>    policy_name: "read-bucket",
      #=>    # URL-encoded JSON, as AWS returns it.
      #=>    policy_document: "%7B%22Version%22%3A%222012-10-17%22..."
      #=>  }}
  """
  @spec get_role_policy(
          role_name :: String.t(),
          policy_name :: String.t(),
          opts :: keyword()
        ) ::
          {:ok, %{role_name: String.t(), policy_name: String.t(), policy_document: map()}}
          | {:error, term()}
  def get_role_policy(role_name, policy_name, opts \\ []) do
    if sandbox?(opts) do
      sandbox_get_role_policy_response(role_name, policy_name, opts)
    else
      do_get_role_policy(role_name, policy_name, opts)
    end
  end

  defp do_get_role_policy(role_name, policy_name, opts) do
    with {:ok, op} <-
           build_operation(
             "GetRolePolicy",
             %{"RoleName" => role_name, "PolicyName" => policy_name},
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      fields =
        xpath(body, ~x"//GetRolePolicyResult"e,
          role_name: ~x"./RoleName/text()"s,
          policy_name: ~x"./PolicyName/text()"s,
          policy_document: ~x"./PolicyDocument/text()"s
        )

      document = fields.policy_document |> URI.decode() |> :json.decode()

      {:ok,
       %{
         role_name: fields.role_name,
         policy_name: fields.policy_name,
         policy_document: document
       }}
    end
  end

  @doc """
  Deletes an inline policy from an IAM role.

  ## Arguments

    * `role_name` - The role name.
    * `policy_name` - The inline policy name.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.delete_role_policy("AppRole", "read-bucket")
      #=> {:ok, %{}}
  """
  @spec delete_role_policy(
          role_name :: String.t(),
          policy_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{}} | {:error, term()}
  def delete_role_policy(role_name, policy_name, opts \\ []) do
    if sandbox?(opts) do
      sandbox_delete_role_policy_response(role_name, policy_name, opts)
    else
      do_delete_role_policy(role_name, policy_name, opts)
    end
  end

  defp do_delete_role_policy(role_name, policy_name, opts) do
    with {:ok, op} <-
           build_operation(
             "DeleteRolePolicy",
             %{"RoleName" => role_name, "PolicyName" => policy_name},
             opts
           ),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Lists the names of inline policies embedded in an IAM role.

  ## Arguments

    * `role_name` - The role name.
    * `opts` - Options including `:marker`, `:max_items`, plus shared options.

  Returns `{:ok, %{policy_names: [String.t()], is_truncated: boolean(), marker: String.t() | nil}}`.

  ## Examples

      AwsSDK.IAM.list_role_policies("AppRole")
      #=> {:ok,
      #=>  %{
      #=>    policy_names: ["read-bucket", "write-logs"],
      #=>    is_truncated: false,
      #=>    marker: nil
      #=>  }}

  Inline policies only; managed policies come from
  `list_attached_role_policies/2`.
  """
  @spec list_role_policies(role_name :: String.t(), opts :: keyword()) ::
          {:ok,
           %{
             policy_names: list(String.t()),
             is_truncated: boolean(),
             marker: String.t() | nil
           }}
          | {:error, term()}
  def list_role_policies(role_name, opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_role_policies_response(role_name, opts)
    else
      do_list_role_policies(role_name, opts)
    end
  end

  defp do_list_role_policies(role_name, opts) do
    params =
      %{"RoleName" => role_name}
      |> maybe_put("Marker", opts[:marker])
      |> maybe_put("MaxItems", opts[:max_items])

    with {:ok, op} <- build_operation("ListRolePolicies", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      policy_names = xpath(body, ~x"//ListRolePoliciesResult/PolicyNames/member/text()"ls)
      is_truncated = xpath(body, ~x"//ListRolePoliciesResult/IsTruncated/text()"s) === "true"
      marker = xpath(body, ~x"//ListRolePoliciesResult/Marker/text()"s)

      {:ok,
       %{
         policy_names: policy_names,
         is_truncated: is_truncated,
         marker: if(marker === "", do: nil, else: marker)
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Policies
  # ---------------------------------------------------------------------------

  @doc """
  Creates a managed IAM policy.

  ## Arguments

    * `name` - The policy name.
    * `policy_document` - Elixir map defining the policy. JSON-encoded before sending.
    * `opts` - Options including `:path`, `:description`, plus shared options.

  ## Examples

      document = %{
        "Version" => "2012-10-17",
        "Statement" => [
          %{"Effect" => "Allow", "Action" => "s3:GetObject", "Resource" => "arn:aws:s3:::bucket/*"}
        ]
      }

      AwsSDK.IAM.create_policy("ReadBucket", document, description: "Read one bucket")
      #=> {:ok,
      #=>  %{
      #=>    policy: %{
      #=>      policy_name: "ReadBucket",
      #=>      policy_id: "ANPA1EXAMPLE",
      #=>      arn: "arn:aws:iam::123456789012:policy/ReadBucket",
      #=>      path: "/",
      #=>      default_version_id: "v1",
      #=>      attachment_count: 0,
      #=>      permissions_boundary_usage_count: 0,
      #=>      is_attachable: "true",
      #=>      description: "Read one bucket",
      #=>      create_date: "2026-01-01T00:00:00Z",
      #=>      update_date: "2026-01-01T00:00:00Z",
      #=>      tags: []
      #=>    }
      #=>  }}
  """
  @spec create_policy(name :: String.t(), policy_document :: map(), opts :: keyword()) ::
          {:ok, %{policy_name: String.t(), policy_id: String.t(), arn: String.t()}}
          | {:error, term()}
  def create_policy(name, policy_document, opts \\ []) do
    if sandbox?(opts) do
      sandbox_create_policy_response(name, opts)
    else
      do_create_policy(name, policy_document, opts)
    end
  end

  defp do_create_policy(name, policy_document, opts) do
    params =
      %{
        "PolicyName" => name,
        "PolicyDocument" => policy_document |> :json.encode() |> IO.iodata_to_binary()
      }
      |> maybe_put("Path", opts[:path])
      |> maybe_put("Description", opts[:description])

    with {:ok, op} <- build_operation("CreatePolicy", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, %{policy: parse_policy(body, ~x"//Policy"e)}}
    end
  end

  @doc """
  Returns information about a managed IAM policy.

  ## Arguments

    * `policy_arn` - The policy ARN.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.get_policy("arn:aws:iam::123456789012:policy/ReadBucket")
      #=> {:ok,
      #=>  %{
      #=>    policy: %{
      #=>      policy_name: "ReadBucket",
      #=>      policy_id: "ANPA1EXAMPLE",
      #=>      arn: "arn:aws:iam::123456789012:policy/ReadBucket",
      #=>      path: "/",
      #=>      default_version_id: "v3",
      #=>      attachment_count: 2,
      #=>      permissions_boundary_usage_count: 0,
      #=>      is_attachable: "true",
      #=>      description: "Read one bucket",
      #=>      create_date: "2026-01-01T00:00:00Z",
      #=>      update_date: "2026-02-01T00:00:00Z",
      #=>      tags: []
      #=>    }
      #=>  }}

  The policy body is not here -- fetch a version with
  `get_policy_version/3`.
  """
  @spec get_policy(policy_arn :: String.t(), opts :: keyword()) ::
          {:ok, map()} | {:error, term()}
  def get_policy(policy_arn, opts \\ []) do
    if sandbox?(opts) do
      sandbox_get_policy_response(policy_arn, opts)
    else
      do_get_policy(policy_arn, opts)
    end
  end

  defp do_get_policy(policy_arn, opts) do
    with {:ok, op} <- build_operation("GetPolicy", %{"PolicyArn" => policy_arn}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, %{policy: parse_policy(body, ~x"//Policy"e)}}
    end
  end

  @doc """
  Returns a specific version of a managed IAM policy, including the policy document.

  The `<Document>` element returned by AWS is URL-encoded JSON; this function
  URI-decodes and JSON-decodes it so `:document` is an Elixir map.

  ## Arguments

    * `policy_arn` - The policy ARN.
    * `version_id` - The version ID (e.g. `"v1"`).
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.get_policy_version("arn:aws:iam::123456789012:policy/ReadBucket", "v3")
      #=> {:ok,
      #=>  %{
      #=>    policy_version: %{
      #=>      version_id: "v3",
      #=>      is_default_version: true,
      #=>      create_date: "2026-02-01T00:00:00Z",
      #=>      # URL-decoded and JSON-decoded, unlike the raw strings elsewhere.
      #=>      document: %{
      #=>        "Version" => "2012-10-17",
      #=>        "Statement" => [
      #=>          %{
      #=>            "Effect" => "Allow",
      #=>            "Action" => "s3:GetObject",
      #=>            "Resource" => "arn:aws:s3:::bucket/*"
      #=>          }
      #=>        ]
      #=>      }
      #=>    }
      #=>  }}
  """
  @spec get_policy_version(policy_arn :: String.t(), version_id :: String.t(), opts :: keyword()) ::
          {:ok,
           %{
             document: map(),
             version_id: String.t(),
             is_default_version: boolean(),
             create_date: String.t()
           }}
          | {:error, term()}
  def get_policy_version(policy_arn, version_id, opts \\ []) do
    if sandbox?(opts) do
      sandbox_get_policy_version_response(policy_arn, version_id, opts)
    else
      do_get_policy_version(policy_arn, version_id, opts)
    end
  end

  defp do_get_policy_version(policy_arn, version_id, opts) do
    with {:ok, op} <-
           build_operation(
             "GetPolicyVersion",
             %{"PolicyArn" => policy_arn, "VersionId" => version_id},
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      fields =
        xpath(body, ~x"//GetPolicyVersionResult/PolicyVersion"e,
          document: ~x"./Document/text()"s,
          version_id: ~x"./VersionId/text()"s,
          is_default_version: ~x"./IsDefaultVersion/text()"s,
          create_date: ~x"./CreateDate/text()"s
        )

      document =
        fields.document
        |> URI.decode()
        |> :json.decode()

      {:ok,
       %{
         policy_version: %{
           document: document,
           version_id: fields.version_id,
           is_default_version: fields.is_default_version === "true",
           create_date: fields.create_date
         }
       }}
    end
  end

  @doc """
  Lists managed IAM policies.

  ## Options

    * `:scope` - `"All"`, `"AWS"`, or `"Local"` (default: `"Local"`).
    * `:only_attached` - If `true`, list only policies attached to an entity.
    * `:path_prefix` - Filter by path prefix.
    * `:max_items` - Maximum number of items.
    * `:marker` - Pagination marker.

  ## Examples

      AwsSDK.IAM.list_policies(scope: "Local", only_attached: true)
      #=> {:ok,
      #=>  %{
      #=>    policies: [
      #=>      %{
      #=>        policy_name: "ReadBucket",
      #=>        policy_id: "ANPA1EXAMPLE",
      #=>        arn: "arn:aws:iam::123456789012:policy/ReadBucket",
      #=>        path: "/",
      #=>        default_version_id: "v3",
      #=>        attachment_count: 2,
      #=>        is_attachable: "true",
      #=>        create_date: "2026-01-01T00:00:00Z",
      #=>        update_date: "2026-02-01T00:00:00Z",
      #=>        tags: []
      #=>      }
      #=>    ],
      #=>    is_truncated: false,
      #=>    marker: nil
      #=>  }}
  """
  @spec list_policies(opts :: keyword()) ::
          {:ok, %{policies: list(map()), is_truncated: boolean(), marker: String.t() | nil}}
          | {:error, term()}
  def list_policies(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_policies_response(opts)
    else
      do_list_policies(opts)
    end
  end

  defp do_list_policies(opts) do
    params =
      %{}
      |> maybe_put("Scope", opts[:scope])
      |> maybe_put("OnlyAttached", opts[:only_attached])
      |> maybe_put("PathPrefix", opts[:path_prefix])
      |> maybe_put("Marker", opts[:marker])
      |> maybe_put("MaxItems", opts[:max_items])

    with {:ok, op} <- build_operation("ListPolicies", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok,
       %{
         policies: parse_policy(body, ~x"//Policies/member"l),
         is_truncated: xpath(body, ~x"//ListPoliciesResult/IsTruncated/text()"s) == "true",
         marker: xpath(body, ~x"//ListPoliciesResult/Marker/text()"so)
       }}
    end
  end

  @doc """
  Deletes a managed IAM policy.

  ## Arguments

    * `policy_arn` - The policy ARN.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.delete_policy("arn:aws:iam::123456789012:policy/ReadBucket")
      #=> {:ok, %{}}

  Non-default versions and all attachments must be removed first.
  """
  @spec delete_policy(policy_arn :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def delete_policy(policy_arn, opts \\ []) do
    if sandbox?(opts) do
      sandbox_delete_policy_response(policy_arn, opts)
    else
      do_delete_policy(policy_arn, opts)
    end
  end

  defp do_delete_policy(policy_arn, opts) do
    with {:ok, op} <- build_operation("DeletePolicy", %{"PolicyArn" => policy_arn}, opts),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Creates a new version of a managed IAM policy.

  ## Arguments

    * `policy_arn` - The policy ARN.
    * `document` - Elixir map of the policy document. JSON-encoded before sending.
    * `opts` - Options including `:set_as_default` (boolean), plus shared options.

  Returns `{:ok, %{policy_version: %{version_id, is_default_version, create_date}}}`.

  ## Examples

      AwsSDK.IAM.create_policy_version(
        "arn:aws:iam::123456789012:policy/ReadBucket",
        document,
        set_as_default: true
      )
      #=> {:ok,
      #=>  %{
      #=>    policy_version: %{
      #=>      version_id: "v4",
      #=>      is_default_version: true,
      #=>      create_date: "2026-03-01T00:00:00Z"
      #=>    }
      #=>  }}

  A policy is capped at five versions; delete one before adding a sixth.
  """
  @spec create_policy_version(
          policy_arn :: String.t(),
          document :: map(),
          opts :: keyword()
        ) :: {:ok, %{policy_version: map()}} | {:error, term()}
  def create_policy_version(policy_arn, document, opts \\ []) do
    if sandbox?(opts) do
      sandbox_create_policy_version_response(policy_arn, opts)
    else
      do_create_policy_version(policy_arn, document, opts)
    end
  end

  defp do_create_policy_version(policy_arn, document, opts) do
    params =
      %{
        "PolicyArn" => policy_arn,
        "PolicyDocument" => document |> :json.encode() |> IO.iodata_to_binary()
      }
      |> maybe_put("SetAsDefault", opts[:set_as_default])

    with {:ok, op} <- build_operation("CreatePolicyVersion", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      fields =
        xpath(body, ~x"//PolicyVersion"e,
          version_id: ~x"./VersionId/text()"s,
          is_default_version: ~x"./IsDefaultVersion/text()"s,
          create_date: ~x"./CreateDate/text()"s
        )

      {:ok,
       %{
         policy_version: %{
           version_id: fields.version_id,
           is_default_version: fields.is_default_version === "true",
           create_date: fields.create_date
         }
       }}
    end
  end

  @doc """
  Sets a specific version of a managed policy as the default version.

  ## Arguments

    * `policy_arn` - The policy ARN.
    * `version_id` - The version ID to promote (e.g. `"v3"`).
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.set_default_policy_version("arn:aws:iam::123456789012:policy/ReadBucket", "v3")
      #=> {:ok, %{}}
  """
  @spec set_default_policy_version(
          policy_arn :: String.t(),
          version_id :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{}} | {:error, term()}
  def set_default_policy_version(policy_arn, version_id, opts \\ []) do
    if sandbox?(opts) do
      sandbox_set_default_policy_version_response(policy_arn, version_id, opts)
    else
      do_set_default_policy_version(policy_arn, version_id, opts)
    end
  end

  defp do_set_default_policy_version(policy_arn, version_id, opts) do
    with {:ok, op} <-
           build_operation(
             "SetDefaultPolicyVersion",
             %{"PolicyArn" => policy_arn, "VersionId" => version_id},
             opts
           ),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Deletes a version of a managed policy. The default version cannot be deleted.

  ## Arguments

    * `policy_arn` - The policy ARN.
    * `version_id` - The version ID to delete.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.delete_policy_version("arn:aws:iam::123456789012:policy/ReadBucket", "v2")
      #=> {:ok, %{}}

  The default version cannot be deleted; promote another first.
  """
  @spec delete_policy_version(
          policy_arn :: String.t(),
          version_id :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{}} | {:error, term()}
  def delete_policy_version(policy_arn, version_id, opts \\ []) do
    if sandbox?(opts) do
      sandbox_delete_policy_version_response(policy_arn, version_id, opts)
    else
      do_delete_policy_version(policy_arn, version_id, opts)
    end
  end

  defp do_delete_policy_version(policy_arn, version_id, opts) do
    with {:ok, op} <-
           build_operation(
             "DeletePolicyVersion",
             %{"PolicyArn" => policy_arn, "VersionId" => version_id},
             opts
           ),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Lists the versions of a managed policy.

  ## Arguments

    * `policy_arn` - The policy ARN.
    * `opts` - Options including `:marker`, `:max_items`, plus shared options.

  Returns `{:ok, %{versions: [map()], is_truncated: boolean(), marker: String.t() | nil}}`
  where each version has `:version_id`, `:is_default_version`, `:create_date`.

  ## Examples

      AwsSDK.IAM.list_policy_versions("arn:aws:iam::123456789012:policy/ReadBucket")
      #=> {:ok,
      #=>  %{
      #=>    versions: [
      #=>      %{version_id: "v3", is_default_version: true, create_date: "2026-02-01T00:00:00Z"},
      #=>      %{version_id: "v2", is_default_version: false, create_date: "2026-01-15T00:00:00Z"}
      #=>    ],
      #=>    is_truncated: false,
      #=>    marker: nil
      #=>  }}

  The documents are not included; fetch one with `get_policy_version/3`.
  """
  @spec list_policy_versions(policy_arn :: String.t(), opts :: keyword()) ::
          {:ok,
           %{
             versions: list(map()),
             is_truncated: boolean(),
             marker: String.t() | nil
           }}
          | {:error, term()}
  def list_policy_versions(policy_arn, opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_policy_versions_response(policy_arn, opts)
    else
      do_list_policy_versions(policy_arn, opts)
    end
  end

  defp do_list_policy_versions(policy_arn, opts) do
    params =
      %{"PolicyArn" => policy_arn}
      |> maybe_put("Marker", opts[:marker])
      |> maybe_put("MaxItems", opts[:max_items])

    with {:ok, op} <- build_operation("ListPolicyVersions", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      versions =
        xpath(body, ~x"//Versions/member"l,
          version_id: ~x"./VersionId/text()"s,
          is_default_version: ~x"./IsDefaultVersion/text()"s,
          create_date: ~x"./CreateDate/text()"s
        )
        |> Enum.map(fn v -> %{v | is_default_version: v.is_default_version === "true"} end)

      is_truncated = xpath(body, ~x"//ListPolicyVersionsResult/IsTruncated/text()"s) === "true"
      marker = xpath(body, ~x"//ListPolicyVersionsResult/Marker/text()"s)

      {:ok,
       %{
         versions: versions,
         is_truncated: is_truncated,
         marker: if(marker === "", do: nil, else: marker)
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Policy attachments
  # ---------------------------------------------------------------------------

  @doc """
  Attaches a managed policy to a role.

  ## Examples

      AwsSDK.IAM.attach_role_policy("AppRole", "arn:aws:iam::aws:policy/ReadOnlyAccess")
      #=> {:ok, %{}}
  """
  @spec attach_role_policy(role_name :: String.t(), policy_arn :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def attach_role_policy(role_name, policy_arn, opts \\ []) do
    if sandbox?(opts) do
      sandbox_attach_role_policy_response(role_name, policy_arn, opts)
    else
      do_attach_role_policy(role_name, policy_arn, opts)
    end
  end

  defp do_attach_role_policy(role_name, policy_arn, opts) do
    with {:ok, op} <-
           build_operation(
             "AttachRolePolicy",
             %{"RoleName" => role_name, "PolicyArn" => policy_arn},
             opts
           ),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Detaches a managed policy from a role.

  ## Examples

      AwsSDK.IAM.detach_role_policy("AppRole", "arn:aws:iam::aws:policy/ReadOnlyAccess")
      #=> {:ok, %{}}
  """
  @spec detach_role_policy(role_name :: String.t(), policy_arn :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def detach_role_policy(role_name, policy_arn, opts \\ []) do
    if sandbox?(opts) do
      sandbox_detach_role_policy_response(role_name, policy_arn, opts)
    else
      do_detach_role_policy(role_name, policy_arn, opts)
    end
  end

  defp do_detach_role_policy(role_name, policy_arn, opts) do
    with {:ok, op} <-
           build_operation(
             "DetachRolePolicy",
             %{"RoleName" => role_name, "PolicyArn" => policy_arn},
             opts
           ),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Lists managed policies attached to a role.

  ## Examples

      AwsSDK.IAM.list_attached_role_policies("AppRole")
      #=> {:ok,
      #=>  %{
      #=>    attached_policies: [
      #=>      %{
      #=>        policy_name: "ReadOnlyAccess",
      #=>        policy_arn: "arn:aws:iam::aws:policy/ReadOnlyAccess"
      #=>      }
      #=>    ],
      #=>    is_truncated: false,
      #=>    marker: nil
      #=>  }}

  The key is `:attached_policies`, AWS's own member name. Inline policies
  come from `list_role_policies/2` instead.
  """
  @spec list_attached_role_policies(role_name :: String.t(), opts :: keyword()) ::
          {:ok,
           %{attached_policies: list(map()), is_truncated: boolean(), marker: String.t() | nil}}
          | {:error, term()}
  def list_attached_role_policies(role_name, opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_attached_role_policies_response(role_name, opts)
    else
      do_list_attached_role_policies(role_name, opts)
    end
  end

  defp do_list_attached_role_policies(role_name, opts) do
    params =
      %{"RoleName" => role_name}
      |> maybe_put("PathPrefix", opts[:path_prefix])
      |> maybe_put("Marker", opts[:marker])
      |> maybe_put("MaxItems", opts[:max_items])

    with {:ok, op} <- build_operation("ListAttachedRolePolicies", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      policies =
        xpath(body, ~x"//AttachedPolicies/member"l,
          policy_name: ~x"./PolicyName/text()"s,
          policy_arn: ~x"./PolicyArn/text()"s
        )

      {:ok,
       %{
         attached_policies: policies,
         is_truncated:
           xpath(body, ~x"//ListAttachedRolePoliciesResult/IsTruncated/text()"s) == "true",
         marker: xpath(body, ~x"//ListAttachedRolePoliciesResult/Marker/text()"so)
       }}
    end
  end

  @doc """
  Attaches a managed policy to a user.

  ## Examples

      AwsSDK.IAM.attach_user_policy("alice", "arn:aws:iam::aws:policy/ReadOnlyAccess")
      #=> {:ok, %{}}
  """
  @spec attach_user_policy(username :: String.t(), policy_arn :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def attach_user_policy(username, policy_arn, opts \\ []) do
    if sandbox?(opts) do
      sandbox_attach_user_policy_response(username, policy_arn, opts)
    else
      do_attach_user_policy(username, policy_arn, opts)
    end
  end

  defp do_attach_user_policy(username, policy_arn, opts) do
    with {:ok, op} <-
           build_operation(
             "AttachUserPolicy",
             %{"UserName" => username, "PolicyArn" => policy_arn},
             opts
           ),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Detaches a managed policy from a user.

  ## Examples

      AwsSDK.IAM.detach_user_policy("alice", "arn:aws:iam::aws:policy/ReadOnlyAccess")
      #=> {:ok, %{}}
  """
  @spec detach_user_policy(username :: String.t(), policy_arn :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def detach_user_policy(username, policy_arn, opts \\ []) do
    if sandbox?(opts) do
      sandbox_detach_user_policy_response(username, policy_arn, opts)
    else
      do_detach_user_policy(username, policy_arn, opts)
    end
  end

  defp do_detach_user_policy(username, policy_arn, opts) do
    with {:ok, op} <-
           build_operation(
             "DetachUserPolicy",
             %{"UserName" => username, "PolicyArn" => policy_arn},
             opts
           ),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Attaches a managed policy to a group.

  ## Examples

      AwsSDK.IAM.attach_group_policy("developers", "arn:aws:iam::aws:policy/ReadOnlyAccess")
      #=> {:ok, %{}}
  """
  @spec attach_group_policy(group_name :: String.t(), policy_arn :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def attach_group_policy(group_name, policy_arn, opts \\ []) do
    if sandbox?(opts) do
      sandbox_attach_group_policy_response(group_name, policy_arn, opts)
    else
      do_attach_group_policy(group_name, policy_arn, opts)
    end
  end

  defp do_attach_group_policy(group_name, policy_arn, opts) do
    with {:ok, op} <-
           build_operation(
             "AttachGroupPolicy",
             %{"GroupName" => group_name, "PolicyArn" => policy_arn},
             opts
           ),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Detaches a managed policy from a group.

  ## Examples

      AwsSDK.IAM.detach_group_policy("developers", "arn:aws:iam::aws:policy/ReadOnlyAccess")
      #=> {:ok, %{}}
  """
  @spec detach_group_policy(group_name :: String.t(), policy_arn :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def detach_group_policy(group_name, policy_arn, opts \\ []) do
    if sandbox?(opts) do
      sandbox_detach_group_policy_response(group_name, policy_arn, opts)
    else
      do_detach_group_policy(group_name, policy_arn, opts)
    end
  end

  defp do_detach_group_policy(group_name, policy_arn, opts) do
    with {:ok, op} <-
           build_operation(
             "DetachGroupPolicy",
             %{"GroupName" => group_name, "PolicyArn" => policy_arn},
             opts
           ),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  # ---------------------------------------------------------------------------
  # MFA Devices
  # ---------------------------------------------------------------------------

  @doc """
  Lists the MFA devices for an IAM user.

  Note: IAM Identity Center users (from the identity store) are distinct from
  IAM users. This action only returns devices for users that exist as IAM users
  (including those created via federation or linked to Identity Center).

  ## Arguments

    * `username` - The IAM user name.
    * `opts` - Options including `:max_items`, `:marker`, plus shared options.

  ## Examples

      AwsSDK.IAM.list_mfa_devices(user_name: "alice")
      #=> {:ok,
      #=>  %{
      #=>    mfa_devices: [
      #=>      %{
      #=>        user_name: "alice",
      #=>        serial_number: "arn:aws:iam::123456789012:mfa/alice",
      #=>        enable_date: "2026-01-01T00:00:00Z"
      #=>      }
      #=>    ],
      #=>    is_truncated: false,
      #=>    marker: nil
      #=>  }}

  A virtual MFA device reports an ARN as its `:serial_number`; a hardware
  device reports the physical serial.
  """
  @spec list_mfa_devices(opts :: keyword()) ::
          {:ok,
           %{
             mfa_devices: list(map()),
             is_truncated: boolean(),
             marker: String.t() | nil
           }}
          | {:error, term()}
  def list_mfa_devices(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_mfa_devices_response(opts)
    else
      do_list_mfa_devices(opts)
    end
  end

  defp do_list_mfa_devices(opts) do
    params =
      maybe_put(%{}, "UserName", opts[:user_name])
      |> maybe_put("Marker", opts[:marker])
      |> maybe_put("MaxItems", opts[:max_items])

    with {:ok, op} <- build_operation("ListMFADevices", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      %{devices: devices, is_truncated: is_truncated, marker: marker} =
        xpath(body, ~x"//ListMFADevicesResult"e,
          devices: [
            ~x"./MFADevices/member"l,
            user_name: ~x"./UserName/text()"s,
            serial_number: ~x"./SerialNumber/text()"s,
            enable_date: ~x"./EnableDate/text()"s
          ],
          is_truncated: ~x"./IsTruncated/text()"s,
          marker: ~x"./Marker/text()"s
        )

      {:ok,
       %{
         mfa_devices: devices,
         is_truncated: is_truncated === "true",
         marker: if(marker === "", do: nil, else: marker)
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # OIDC Providers
  # ---------------------------------------------------------------------------

  @doc """
  Creates an OpenID Connect (OIDC) identity provider in IAM.

  ## Arguments

    * `url` - The OIDC provider URL.
    * `client_id_list` - List of client IDs (audiences).
    * `opts` - Options including `:thumbprint_list` (required by AWS — list of
      server certificate thumbprints), plus shared options.

  ## Examples

      AwsSDK.IAM.create_open_id_connect_provider(
        "https://token.actions.githubusercontent.com",
        ["sts.amazonaws.com"],
        thumbprints: ["6938fd4d98bab03faadb97b34396831e3780aea1"]
      )
      #=> {:ok,
      #=>  %{
      #=>    open_id_connect_provider_arn:
      #=>      "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      #=>  }}
  """
  @spec create_open_id_connect_provider(url :: String.t(), opts :: keyword()) ::
          {:ok, %{open_id_connect_provider_arn: String.t()}} | {:error, term()}
  def create_open_id_connect_provider(url, opts \\ []) when is_binary(url) do
    if sandbox?(opts) do
      sandbox_create_open_id_connect_provider_response(url, opts)
    else
      do_create_open_id_connect_provider(url, opts)
    end
  end

  defp do_create_open_id_connect_provider(url, opts) do
    # Both ClientIDList and ThumbprintList are optional -- IAM now uses its own
    # trusted-CA library rather than requiring thumbprints.
    params =
      %{"Url" => url}
      |> put_member_list("ClientIDList", opts[:client_id_list] || [])
      |> put_member_list("ThumbprintList", opts[:thumbprint_list] || [])

    with {:ok, op} <- build_operation("CreateOpenIDConnectProvider", params, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      arn = xpath(body, ~x"//OpenIDConnectProviderArn/text()"s)
      {:ok, %{open_id_connect_provider_arn: arn}}
    end
  end

  @doc """
  Returns information about an OIDC provider.

  ## Arguments

    * `provider_arn` - The OIDC provider ARN.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.get_open_id_connect_provider(
        "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      )
      #=> {:ok,
      #=>  %{
      #=>    url: "token.actions.githubusercontent.com",
      #=>    client_id_list: ["sts.amazonaws.com"],
      #=>    thumbprint_list: ["6938fd4d98bab03faadb97b34396831e3780aea1"],
      #=>    create_date: "2026-01-01T00:00:00Z",
      #=>    tags: []
      #=>  }}

  AWS returns `:url` without the `https://` scheme it was created with.
  """
  @spec get_open_id_connect_provider(provider_arn :: String.t(), opts :: keyword()) ::
          {:ok,
           %{
             url: String.t(),
             client_id_list: list(String.t()),
             thumbprint_list: list(String.t()),
             create_date: String.t()
           }}
          | {:error, term()}
  def get_open_id_connect_provider(provider_arn, opts \\ []) do
    if sandbox?(opts) do
      sandbox_get_open_id_connect_provider_response(provider_arn, opts)
    else
      do_get_open_id_connect_provider(provider_arn, opts)
    end
  end

  defp do_get_open_id_connect_provider(provider_arn, opts) do
    with {:ok, op} <-
           build_operation(
             "GetOpenIDConnectProvider",
             %{"OpenIDConnectProviderArn" => provider_arn},
             opts
           ),
         {:ok, %{body: body}} <- Client.request(op) do
      fields =
        xpath(body, ~x"//GetOpenIDConnectProviderResult"e,
          url: ~x"./Url/text()"s,
          client_id_list: ~x"./ClientIDList/member/text()"ls,
          thumbprint_list: ~x"./ThumbprintList/member/text()"ls,
          tags: [~x"./Tags/member"l, key: ~x"./Key/text()"s, value: ~x"./Value/text()"s],
          create_date: ~x"./CreateDate/text()"s
        )

      {:ok, fields}
    end
  end

  @doc """
  Lists the OIDC providers in the account.

  ## Examples

      AwsSDK.IAM.list_open_id_connect_providers()
      #=> {:ok,
      #=>  %{
      #=>    open_id_connect_provider_list: [
      #=>      %{arn: "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"}
      #=>    ]
      #=>  }}

  ARNs only; call `get_open_id_connect_provider/2` for the details.
  """
  @spec list_open_id_connect_providers(opts :: keyword()) ::
          {:ok, %{open_id_connect_provider_list: list(%{arn: String.t()})}}
          | {:error, term()}
  def list_open_id_connect_providers(opts \\ []) do
    if sandbox?(opts) do
      sandbox_list_open_id_connect_providers_response(opts)
    else
      do_list_open_id_connect_providers(opts)
    end
  end

  defp do_list_open_id_connect_providers(opts) do
    with {:ok, op} <- build_operation("ListOpenIDConnectProviders", %{}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      providers =
        xpath(body, ~x"//OpenIDConnectProviderList/member"l, arn: ~x"./Arn/text()"s)

      {:ok, %{open_id_connect_provider_list: providers}}
    end
  end

  @doc """
  Deletes an OIDC provider.

  ## Arguments

    * `provider_arn` - The OIDC provider ARN.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.delete_open_id_connect_provider(
        "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      )
      #=> {:ok, %{}}
  """
  @spec delete_open_id_connect_provider(provider_arn :: String.t(), opts :: keyword()) ::
          {:ok, %{}} | {:error, term()}
  def delete_open_id_connect_provider(provider_arn, opts \\ []) do
    if sandbox?(opts) do
      sandbox_delete_open_id_connect_provider_response(provider_arn, opts)
    else
      do_delete_open_id_connect_provider(provider_arn, opts)
    end
  end

  defp do_delete_open_id_connect_provider(provider_arn, opts) do
    with {:ok, op} <-
           build_operation(
             "DeleteOpenIDConnectProvider",
             %{"OpenIDConnectProviderArn" => provider_arn},
             opts
           ),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Replaces the list of server certificate thumbprints on an OIDC provider.

  ## Arguments

    * `provider_arn` - The OIDC provider ARN.
    * `thumbprint_list` - New list of thumbprints.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.update_open_id_connect_provider_thumbprint(
        "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com",
        ["6938fd4d98bab03faadb97b34396831e3780aea1"]
      )
      #=> {:ok, %{}}

  The list replaces the existing thumbprints outright rather than adding to
  them.
  """
  @spec update_open_id_connect_provider_thumbprint(
          provider_arn :: String.t(),
          thumbprint_list :: list(String.t()),
          opts :: keyword()
        ) :: {:ok, %{}} | {:error, term()}
  def update_open_id_connect_provider_thumbprint(provider_arn, thumbprint_list, opts \\ []) do
    if sandbox?(opts) do
      sandbox_update_open_id_connect_provider_thumbprint_response(provider_arn, opts)
    else
      do_update_open_id_connect_provider_thumbprint(provider_arn, thumbprint_list, opts)
    end
  end

  defp do_update_open_id_connect_provider_thumbprint(provider_arn, thumbprint_list, opts) do
    params =
      %{"OpenIDConnectProviderArn" => provider_arn}
      |> put_member_list("ThumbprintList", thumbprint_list)

    with {:ok, op} <- build_operation("UpdateOpenIDConnectProviderThumbprint", params, opts),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Adds a client ID (audience) to an OIDC provider.

  ## Arguments

    * `provider_arn` - The OIDC provider ARN.
    * `client_id` - The client ID to add.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.add_client_id_to_open_id_connect_provider(
        "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com",
        "sts.amazonaws.com"
      )
      #=> {:ok, %{}}
  """
  @spec add_client_id_to_open_id_connect_provider(
          provider_arn :: String.t(),
          client_id :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{}} | {:error, term()}
  def add_client_id_to_open_id_connect_provider(provider_arn, client_id, opts \\ []) do
    if sandbox?(opts) do
      sandbox_add_client_id_to_open_id_connect_provider_response(provider_arn, opts)
    else
      do_add_client_id_to_open_id_connect_provider(provider_arn, client_id, opts)
    end
  end

  defp do_add_client_id_to_open_id_connect_provider(provider_arn, client_id, opts) do
    with {:ok, op} <-
           build_operation(
             "AddClientIDToOpenIDConnectProvider",
             %{"OpenIDConnectProviderArn" => provider_arn, "ClientID" => client_id},
             opts
           ),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  @doc """
  Removes a client ID (audience) from an OIDC provider.

  ## Arguments

    * `provider_arn` - The OIDC provider ARN.
    * `client_id` - The client ID to remove.
    * `opts` - Shared options.

  ## Examples

      AwsSDK.IAM.remove_client_id_from_open_id_connect_provider(
        "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com",
        "sts.amazonaws.com"
      )
      #=> {:ok, %{}}
  """
  @spec remove_client_id_from_open_id_connect_provider(
          provider_arn :: String.t(),
          client_id :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{}} | {:error, term()}
  def remove_client_id_from_open_id_connect_provider(provider_arn, client_id, opts \\ []) do
    if sandbox?(opts) do
      sandbox_remove_client_id_from_open_id_connect_provider_response(provider_arn, opts)
    else
      do_remove_client_id_from_open_id_connect_provider(provider_arn, client_id, opts)
    end
  end

  defp do_remove_client_id_from_open_id_connect_provider(provider_arn, client_id, opts) do
    with {:ok, op} <-
           build_operation(
             "RemoveClientIDFromOpenIDConnectProvider",
             %{"OpenIDConnectProviderArn" => provider_arn, "ClientID" => client_id},
             opts
           ),
         {:ok, %{body: _body}} <- Client.request(op) do
      {:ok, %{}}
    end
  end

  # ---------------------------------------------------------------------------
  # Account
  # ---------------------------------------------------------------------------

  @doc """
  Returns a summary of IAM entities in the current account.

  Wraps the IAM `GetAccountSummary` action. The response is a flat map of
  integer-valued account attributes such as `"AccountAccessKeysPresent"`,
  `"AccountMFAEnabled"`, `"Users"`, `"Groups"`, `"Roles"`, etc.

  Returns `{:ok, %{summary_map: [%{key: String.t(), value: integer()}]}}`.
  AWS sends `SummaryMap` as a list of `<entry><key/><value/></entry>`
  elements, and that list is what comes back.

  ## Examples

      AwsSDK.IAM.get_account_summary()
      #=> {:ok,
      #=>  %{
      #=>    summary_map: [
      #=>      %{key: "Users", value: 12},
      #=>      %{key: "UsersQuota", value: 5000},
      #=>      %{key: "Groups", value: 3},
      #=>      %{key: "Policies", value: 27},
      #=>      %{key: "MFADevices", value: 8},
      #=>      %{key: "AccountMFAEnabled", value: 1}
      #=>    ]
      #=>  }}

  AWS sends `SummaryMap` as a list of `<entry><key/><value/></entry>`, so a
  list is what comes back. Build a map yourself if you want lookup:

      {:ok, %{summary_map: entries}} = AwsSDK.IAM.get_account_summary()
      Map.new(entries, &{&1.key, &1.value})
      #=> %{"Users" => 12, "UsersQuota" => 5000, ...}
  """
  @spec get_account_summary(opts :: keyword()) ::
          {:ok, %{summary_map: list(map())}} | {:error, term()}
  def get_account_summary(opts \\ []) do
    if sandbox?(opts) do
      sandbox_get_account_summary_response(opts)
    else
      do_get_account_summary(opts)
    end
  end

  defp do_get_account_summary(opts) do
    with {:ok, op} <- build_operation("GetAccountSummary", %{}, opts),
         {:ok, %{body: body}} <- Client.request(op) do
      {:ok, parse_account_summary(body)}
    end
  end

  @doc false
  def parse_account_summary_for_test(xml), do: parse_account_summary(xml)

  # AWS sends SummaryMap as a list of <entry><key/><value/></entry>, so that
  # is what comes back. Collapsing it to a plain map would be this library
  # choosing a container AWS did not send.
  defp parse_account_summary(body) do
    %{
      summary_map:
        xpath(body, ~x"//GetAccountSummaryResult/SummaryMap/entry"l,
          key: ~x"./key/text()"s,
          value: ~x"./value/text()"i
        )
    }
  end

  # ---------------------------------------------------------------------------
  # Sandbox delegation
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @doc false
  def build_operation(action, params, opts) do
    opts = Keyword.put_new(opts, :region, @default_region)

    with {:ok, config} <- Client.resolve_config(:iam, opts, fn _region -> @default_host end) do
      op = %Operation{
        method: :post,
        url: Client.simple_url(config),
        headers: [{"content-type", @content_type}],
        body: encode_body(action, params),
        service: @service,
        region: config.region,
        access_key_id: config.access_key_id,
        secret_access_key: config.secret_access_key,
        security_token: config.security_token,
        http: Keyword.get(opts, :http, [])
      }

      {:ok, apply_overrides(op, opts[:iam] || [])}
    end
  end

  defp encode_body(action, params) do
    params
    |> Map.merge(%{"Action" => action, "Version" => @api_version})
    |> URI.encode_query()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp put_member_list(map, prefix, values) when is_list(values) do
    values
    |> Enum.with_index(1)
    |> Enum.reduce(map, fn {value, idx}, acc ->
      Map.put(acc, "#{prefix}.member.#{idx}", value)
    end)
  end

  defp parse_user(body, path) do
    xpath(body, path,
      user_name: ~x"./UserName/text()"s,
      user_id: ~x"./UserId/text()"s,
      arn: ~x"./Arn/text()"s,
      path: ~x"./Path/text()"s,
      create_date: ~x"./CreateDate/text()"s,
      # Returned only by GetUser and ListUsers, and null if never signed in.
      password_last_used: ~x"./PasswordLastUsed/text()"os,
      permissions_boundary: [
        ~x"./PermissionsBoundary"o,
        permissions_boundary_arn: ~x"./PermissionsBoundaryArn/text()"os,
        permissions_boundary_type: ~x"./PermissionsBoundaryType/text()"os
      ],
      tags: [~x"./Tags/member"l, key: ~x"./Key/text()"s, value: ~x"./Value/text()"s]
    )
  end

  defp parse_access_key(body, path) do
    xpath(body, path,
      access_key_id: ~x"./AccessKeyId/text()"s,
      secret_access_key: ~x"./SecretAccessKey/text()"s,
      user_name: ~x"./UserName/text()"s,
      status: ~x"./Status/text()"s,
      # Omitted from the CreateAccessKey sample despite the shape page.
      create_date: ~x"./CreateDate/text()"os
    )
  end

  defp parse_group(body, path) do
    xpath(body, path,
      group_name: ~x"./GroupName/text()"s,
      group_id: ~x"./GroupId/text()"s,
      arn: ~x"./Arn/text()"s,
      path: ~x"./Path/text()"s,
      create_date: ~x"./CreateDate/text()"s
    )
  end

  @doc false
  def parse_role_for_test(xml), do: parse_role(xml, ~x"//Role"e)

  defp parse_role(body, path) do
    xpath(body, path,
      role_name: ~x"./RoleName/text()"s,
      role_id: ~x"./RoleId/text()"s,
      arn: ~x"./Arn/text()"s,
      path: ~x"./Path/text()"s,
      create_date: ~x"./CreateDate/text()"s,
      # URL-encoded per RFC 3986 -- the GetRole operation note says so, even
      # though the doc samples show it decoded.
      assume_role_policy_document: ~x"./AssumeRolePolicyDocument/text()"os,
      description: ~x"./Description/text()"os,
      # Required: No, and absent from the GetRole/CreateRole/ListRoles samples.
      max_session_duration: ~x"./MaxSessionDuration/text()"oi,
      permissions_boundary: [
        ~x"./PermissionsBoundary"o,
        permissions_boundary_arn: ~x"./PermissionsBoundaryArn/text()"os,
        permissions_boundary_type: ~x"./PermissionsBoundaryType/text()"os
      ],
      role_last_used: [
        ~x"./RoleLastUsed"o,
        last_used_date: ~x"./LastUsedDate/text()"os,
        region: ~x"./Region/text()"os
      ],
      tags: [~x"./Tags/member"l, key: ~x"./Key/text()"s, value: ~x"./Value/text()"s]
    )
  end

  defp parse_policy(body, path) do
    xpath(body, path,
      policy_name: ~x"./PolicyName/text()"s,
      policy_id: ~x"./PolicyId/text()"s,
      arn: ~x"./Arn/text()"s,
      path: ~x"./Path/text()"s,
      create_date: ~x"./CreateDate/text()"s,
      update_date: ~x"./UpdateDate/text()"s,
      default_version_id: ~x"./DefaultVersionId/text()"s,
      # Every Policy member is Required: No. PermissionsBoundaryUsageCount in
      # particular is absent from the GetPolicy and CreatePolicy samples.
      attachment_count: ~x"./AttachmentCount/text()"oi,
      permissions_boundary_usage_count: ~x"./PermissionsBoundaryUsageCount/text()"oi,
      is_attachable: ~x"./IsAttachable/text()"os,
      # Included in GetPolicy but not in ListPolicies.
      description: ~x"./Description/text()"os,
      tags: [~x"./Tags/member"l, key: ~x"./Key/text()"s, value: ~x"./Value/text()"s]
    )
  end

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
    defdelegate sandbox_disabled?, to: AwsSDK.IAM.Sandbox

    # Users
    @doc false
    defdelegate sandbox_create_user_response(name, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :create_user_response

    @doc false
    defdelegate sandbox_get_user_response(opts), to: AwsSDK.IAM.Sandbox, as: :get_user_response
    @doc false
    defdelegate sandbox_list_users_response(opts),
      to: AwsSDK.IAM.Sandbox,
      as: :list_users_response

    @doc false
    defdelegate sandbox_delete_user_response(name, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :delete_user_response

    # Access Keys
    @doc false
    defdelegate sandbox_create_access_key_response(opts),
      to: AwsSDK.IAM.Sandbox,
      as: :create_access_key_response

    @doc false
    defdelegate sandbox_list_access_keys_response(opts),
      to: AwsSDK.IAM.Sandbox,
      as: :list_access_keys_response

    @doc false
    defdelegate sandbox_delete_access_key_response(key_id, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :delete_access_key_response

    # Groups
    @doc false
    defdelegate sandbox_create_group_response(name, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :create_group_response

    @doc false
    defdelegate sandbox_list_groups_response(opts),
      to: AwsSDK.IAM.Sandbox,
      as: :list_groups_response

    @doc false
    defdelegate sandbox_delete_group_response(name, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :delete_group_response

    # Group membership
    @doc false
    defdelegate sandbox_add_user_to_group_response(group, user, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :add_user_to_group_response

    @doc false
    defdelegate sandbox_remove_user_from_group_response(group, user, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :remove_user_from_group_response

    # Roles
    @doc false
    defdelegate sandbox_create_role_response(name, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :create_role_response

    @doc false
    defdelegate sandbox_get_role_response(name, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :get_role_response

    @doc false
    defdelegate sandbox_get_instance_profile_response(instance_profile_name, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :get_instance_profile_response

    @doc false
    defdelegate sandbox_list_roles_response(opts),
      to: AwsSDK.IAM.Sandbox,
      as: :list_roles_response

    @doc false
    defdelegate sandbox_delete_role_response(name, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :delete_role_response

    # Policies
    @doc false
    defdelegate sandbox_create_policy_response(name, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :create_policy_response

    @doc false
    defdelegate sandbox_get_policy_response(arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :get_policy_response

    @doc false
    defdelegate sandbox_get_policy_version_response(arn, version_id, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :get_policy_version_response

    @doc false
    defdelegate sandbox_list_policies_response(opts),
      to: AwsSDK.IAM.Sandbox,
      as: :list_policies_response

    @doc false
    defdelegate sandbox_delete_policy_response(arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :delete_policy_response

    @doc false
    defdelegate sandbox_create_policy_version_response(arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :create_policy_version_response

    @doc false
    defdelegate sandbox_set_default_policy_version_response(arn, version_id, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :set_default_policy_version_response

    @doc false
    defdelegate sandbox_delete_policy_version_response(arn, version_id, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :delete_policy_version_response

    @doc false
    defdelegate sandbox_list_policy_versions_response(arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :list_policy_versions_response

    # Attachments
    @doc false
    defdelegate sandbox_attach_role_policy_response(role, arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :attach_role_policy_response

    @doc false
    defdelegate sandbox_detach_role_policy_response(role, arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :detach_role_policy_response

    @doc false
    defdelegate sandbox_list_attached_role_policies_response(role, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :list_attached_role_policies_response

    @doc false
    defdelegate sandbox_attach_user_policy_response(user, arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :attach_user_policy_response

    @doc false
    defdelegate sandbox_detach_user_policy_response(user, arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :detach_user_policy_response

    @doc false
    defdelegate sandbox_attach_group_policy_response(group, arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :attach_group_policy_response

    @doc false
    defdelegate sandbox_detach_group_policy_response(group, arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :detach_group_policy_response

    # MFA Devices
    @doc false
    defdelegate sandbox_list_mfa_devices_response(opts),
      to: AwsSDK.IAM.Sandbox,
      as: :list_mfa_devices_response

    # Role Policies
    @doc false
    defdelegate sandbox_update_assume_role_policy_response(role_name, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :update_assume_role_policy_response

    @doc false
    defdelegate sandbox_put_role_policy_response(role_name, policy_name, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :put_role_policy_response

    @doc false
    defdelegate sandbox_get_role_policy_response(role_name, policy_name, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :get_role_policy_response

    @doc false
    defdelegate sandbox_delete_role_policy_response(role_name, policy_name, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :delete_role_policy_response

    @doc false
    defdelegate sandbox_list_role_policies_response(role_name, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :list_role_policies_response

    # OIDC Providers
    @doc false
    defdelegate sandbox_create_open_id_connect_provider_response(url, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :create_open_id_connect_provider_response

    @doc false
    defdelegate sandbox_get_open_id_connect_provider_response(arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :get_open_id_connect_provider_response

    @doc false
    defdelegate sandbox_list_open_id_connect_providers_response(opts),
      to: AwsSDK.IAM.Sandbox,
      as: :list_open_id_connect_providers_response

    @doc false
    defdelegate sandbox_delete_open_id_connect_provider_response(arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :delete_open_id_connect_provider_response

    @doc false
    defdelegate sandbox_update_open_id_connect_provider_thumbprint_response(arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :update_open_id_connect_provider_thumbprint_response

    @doc false
    defdelegate sandbox_add_client_id_to_open_id_connect_provider_response(arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :add_client_id_to_open_id_connect_provider_response

    @doc false
    defdelegate sandbox_remove_client_id_from_open_id_connect_provider_response(arn, opts),
      to: AwsSDK.IAM.Sandbox,
      as: :remove_client_id_from_open_id_connect_provider_response

    @doc false
    defdelegate sandbox_get_account_summary_response(opts),
      to: AwsSDK.IAM.Sandbox,
      as: :get_account_summary_response
  else
    defp sandbox_disabled?, do: true

    # Users
    defp sandbox_create_user_response(_, _), do: raise("sandbox not available")
    defp sandbox_get_user_response(_o), do: raise("sandbox not available")
    defp sandbox_list_users_response(_), do: raise("sandbox not available")
    defp sandbox_delete_user_response(_, _), do: raise("sandbox not available")

    # Access Keys
    defp sandbox_create_access_key_response(_o), do: raise("sandbox not available")
    defp sandbox_list_access_keys_response(_o), do: raise("sandbox not available")
    defp sandbox_delete_access_key_response(_k, _o), do: raise("sandbox not available")

    # Groups
    defp sandbox_create_group_response(_, _), do: raise("sandbox not available")
    defp sandbox_list_groups_response(_), do: raise("sandbox not available")
    defp sandbox_delete_group_response(_, _), do: raise("sandbox not available")

    # Group membership
    defp sandbox_add_user_to_group_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_remove_user_from_group_response(_, _, _), do: raise("sandbox not available")

    # Roles
    defp sandbox_create_role_response(_, _), do: raise("sandbox not available")
    defp sandbox_get_role_response(_, _), do: raise("sandbox not available")
    defp sandbox_get_instance_profile_response(_, _), do: raise("sandbox not available")
    defp sandbox_list_roles_response(_), do: raise("sandbox not available")
    defp sandbox_delete_role_response(_, _), do: raise("sandbox not available")

    # Policies
    defp sandbox_create_policy_response(_, _), do: raise("sandbox not available")
    defp sandbox_get_policy_response(_, _), do: raise("sandbox not available")
    defp sandbox_get_policy_version_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_list_policies_response(_), do: raise("sandbox not available")
    defp sandbox_delete_policy_response(_, _), do: raise("sandbox not available")
    defp sandbox_create_policy_version_response(_, _), do: raise("sandbox not available")
    defp sandbox_set_default_policy_version_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_delete_policy_version_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_list_policy_versions_response(_, _), do: raise("sandbox not available")

    # Attachments
    defp sandbox_attach_role_policy_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_detach_role_policy_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_list_attached_role_policies_response(_, _), do: raise("sandbox not available")
    defp sandbox_attach_user_policy_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_detach_user_policy_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_attach_group_policy_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_detach_group_policy_response(_, _, _), do: raise("sandbox not available")

    # MFA Devices
    defp sandbox_list_mfa_devices_response(_o), do: raise("sandbox not available")

    # Role Policies
    defp sandbox_update_assume_role_policy_response(_, _), do: raise("sandbox not available")
    defp sandbox_put_role_policy_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_get_role_policy_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_delete_role_policy_response(_, _, _), do: raise("sandbox not available")
    defp sandbox_list_role_policies_response(_, _), do: raise("sandbox not available")

    # OIDC Providers
    defp sandbox_create_open_id_connect_provider_response(_, _),
      do: raise("sandbox not available")

    defp sandbox_get_open_id_connect_provider_response(_, _),
      do: raise("sandbox not available")

    defp sandbox_list_open_id_connect_providers_response(_),
      do: raise("sandbox not available")

    defp sandbox_delete_open_id_connect_provider_response(_, _),
      do: raise("sandbox not available")

    defp sandbox_update_open_id_connect_provider_thumbprint_response(_, _),
      do: raise("sandbox not available")

    defp sandbox_add_client_id_to_open_id_connect_provider_response(_, _),
      do: raise("sandbox not available")

    defp sandbox_remove_client_id_from_open_id_connect_provider_response(_, _),
      do: raise("sandbox not available")

    defp sandbox_get_account_summary_response(_opts), do: raise("sandbox not available")
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
end
