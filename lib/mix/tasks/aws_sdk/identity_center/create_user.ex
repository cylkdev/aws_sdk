defmodule Mix.Tasks.AwsSDK.IdentityCenter.CreateUser do
  @shortdoc "Creates a user in the Identity Center identity store"

  @moduledoc """
  Creates a user in the IAM Identity Center identity store.

  ## Usage

      mix aws_sdk.identity_center.create_user --identity-store-id ID --username NAME [options]

  ## Options

    * `--identity-store-id` — Identity store ID (required)
    * `--username` — User name (required)
    * `--display-name` — Full display name for the user
    * `--given-name` — First name
    * `--family-name` — Last name
    * `--email` — Primary email address
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.identity_center.create_user --identity-store-id d-123456 --username alice --display-name "Alice Smith" --email alice@example.com
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
      Helpers.parse_opts(argv,
        identity_store_id: :string,
        username: :string,
        display_name: :string,
        given_name: :string,
        family_name: :string,
        email: :string
      )

    identity_store_id = parsed[:identity_store_id] || Mix.raise("--identity-store-id is required")
    username = parsed[:username] || Mix.raise("--username is required")

    opts =
      Helpers.build_opts(parsed)
      |> Helpers.maybe_put(:display_name, parsed[:display_name])
      |> Helpers.maybe_put(:given_name, parsed[:given_name])
      |> Helpers.maybe_put(:family_name, parsed[:family_name])
      |> then(fn o ->
        case parsed[:email] do
          nil ->
            o

          email ->
            Keyword.put(o, :emails, [%{"Value" => email, "Type" => "work", "Primary" => true}])
        end
      end)

    identity_store_id
    |> AwsSDK.IdentityCenter.create_identity_store_user(username, opts)
    |> Helpers.handle_result()
  end
end
