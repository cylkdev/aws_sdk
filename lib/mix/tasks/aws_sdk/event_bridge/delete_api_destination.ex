defmodule Mix.Tasks.AwsSDK.Eventbridge.DeleteApiDestination do
  @shortdoc "Deletes an EventBridge API destination"

  @moduledoc """
  Deletes an EventBridge API destination.

  ## Usage

      mix aws_sdk.eventbridge.delete_api_destination NAME [options]

  ## Options

    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.eventbridge.delete_api_destination my-dest
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
    {parsed, args, _} = Helpers.parse_opts(argv)

    name =
      List.first(args) || Mix.raise("Usage: mix aws_sdk.eventbridge.delete_api_destination NAME")

    opts = Helpers.build_opts(parsed)

    name
    |> AwsSDK.EventBridge.delete_api_destination(opts)
    |> Helpers.handle_result()
  end
end
