defmodule Mix.Tasks.AwsSDK.IdentityCenter.ListUsers do
  @shortdoc "Lists users in the Identity Center identity store"

  @moduledoc """
  Lists users in the IAM Identity Center identity store.

  ## Usage

      mix aws_sdk.identity_center.list_users --identity-store-id ID [options]

  ## Options

    * `--identity-store-id` — Identity store ID (required)
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.identity_center.list_users --identity-store-id d-123456
  """

  use Mix.Task
  alias Mix.Tasks.AwsSDK.Helpers

  # @requirements declares the Mix tasks that must run before this task.
  #
  # When this task is invoked, Mix runs each requirement once with Mix.Task.run/2
  # before calling this task's run/1 function.
  #
  # This makes task dependencies explicit in the task definition instead of
  # requiring run/1 to start dependencies manually or requiring callers to compose
  # tasks themselves.
  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {parsed, _args, _} = Helpers.parse_opts(argv, identity_store_id: :string)

    identity_store_id = parsed[:identity_store_id] || Mix.raise("--identity-store-id is required")

    opts = Helpers.build_opts(parsed)

    identity_store_id
    |> AwsSDK.IdentityCenter.list_identity_store_users(opts)
    |> Helpers.handle_result()
  end
end
