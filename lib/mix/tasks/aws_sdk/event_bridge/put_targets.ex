defmodule Mix.Tasks.AwsSDK.Eventbridge.PutTargets do
  @shortdoc "Adds a target to an EventBridge rule"

  @moduledoc """
  Adds a target to an EventBridge rule. Skips if a target with the same ID already
  exists unless `--force` is given.

  ## Usage

      mix aws_sdk.eventbridge.put_targets RULE --target-id ID --target-arn ARN [options]

  ## Options

    * `--target-id` — Unique ID for the target (required)
    * `--target-arn` — ARN of the target resource (required)
    * `--role-arn` — IAM role ARN for EventBridge to assume when invoking the target
    * `--input` — JSON string to send to the target instead of the full event
    * `--input-path` — JSONPath expression to extract a portion of the event
    * `--event-bus-name` — Custom event bus name
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)
    * `--force` / `-f` — Update the target if it already exists

  ## Examples

      mix aws_sdk.eventbridge.put_targets my-rule --target-id my-queue --target-arn arn:aws:sqs:...
      mix aws_sdk.eventbridge.put_targets my-rule --target-id my-fn --target-arn arn:aws:lambda:... --force
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
    {parsed, args, _} =
      Helpers.parse_opts(argv,
        target_id: :string,
        target_arn: :string,
        role_arn: :string,
        input: :string,
        input_path: :string
      )

    rule =
      List.first(args) ||
        Mix.raise(
          "Usage: mix aws_sdk.eventbridge.put_targets RULE --target-id ID --target-arn ARN"
        )

    target_id = parsed[:target_id] || Mix.raise("--target-id is required")
    target_arn = parsed[:target_arn] || Mix.raise("--target-arn is required")

    opts = Helpers.build_opts(parsed)
    force = parsed[:force] || false

    target =
      %{id: target_id, arn: target_arn}
      |> maybe_put(:role_arn, parsed[:role_arn])
      |> maybe_put(:input, parsed[:input])
      |> maybe_put(:input_path, parsed[:input_path])

    Helpers.idempotent(
      target_id,
      fn -> Helpers.find_target(rule, target_id, opts) end,
      fn ->
        Helpers.handle_result(AwsSDK.EventBridge.put_targets(rule, [target], opts))
      end,
      force
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
