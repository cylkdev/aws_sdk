defmodule Mix.Tasks.AwsSDK.IdentityCenter.CreateGroup do
  @shortdoc "Creates a group in the Identity Center identity store"

  @moduledoc """
  Creates a group in the IAM Identity Center identity store.

  ## Usage

      mix aws_sdk.identity_center.create_group --identity-store-id ID --name NAME [options]

  ## Options

    * `--identity-store-id` — Identity store ID (required)
    * `--name` — Group display name (required)
    * `--description` — Group description
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.identity_center.create_group --identity-store-id d-123456 --name "Engineering Team" --description "All engineers"
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
    {parsed, _args, _} =
      Helpers.parse_opts(argv, identity_store_id: :string, name: :string, description: :string)

    identity_store_id = parsed[:identity_store_id] || Mix.raise("--identity-store-id is required")
    display_name = parsed[:name] || Mix.raise("--name is required")

    opts =
      parsed
      |> Helpers.build_opts()
      |> Helpers.maybe_put(:description, parsed[:description])

    identity_store_id
    |> AwsSDK.IdentityCenter.create_identity_store_group(display_name, opts)
    |> Helpers.handle_result()
  end
end
