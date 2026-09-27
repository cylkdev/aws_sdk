defmodule Mix.Tasks.AwsSDK.S3.EnableEventBridge do
  @shortdoc "Enables EventBridge notifications on an S3 bucket"

  @moduledoc """
  Enables EventBridge notifications on an S3 bucket.

  Once enabled, all S3 event types are forwarded to EventBridge. Filtering by
  event type is done at the rule level. This operation is idempotent.

  ## Usage

      mix aws_sdk.s3.enable_event_bridge BUCKET [options]

  ## Options

    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.s3.enable_event_bridge my-bucket
      mix aws_sdk.s3.enable_event_bridge my-bucket --region us-east-1
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

    bucket = List.first(args) || Mix.raise("Usage: mix aws_sdk.s3.enable_event_bridge BUCKET")
    opts = Helpers.build_opts(parsed)

    bucket
    |> AwsSDK.S3.enable_event_bridge(opts)
    |> Helpers.handle_result()
  end
end
