defmodule AwsSDK.Credentials.Providers.LoginSession do
  @moduledoc """
  Resolves credentials for profiles populated by `aws login` (introduced
  in [AWS CLI v2.32.0, November 2025](https://aws.amazon.com/blogs/security/simplified-developer-access-to-aws-with-aws-login/)).
  These profiles carry a `login_session` key naming the IAM principal:

      [profile dev]
      login_session = arn:aws:iam::123456789012:user/dev
      region = us-east-1

  ## Why we shell out instead of reading the cache

  AWS does not publish the schema of the on-disk cache at
  `~/.aws/login/cache/<hash>.json` and explicitly steers SDKs to the
  `credential_process` shim:
  https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html.

  This provider follows that contract. On a cache miss in
  `AwsSDK.AuthCache`, it invokes:

      aws configure export-credentials --profile <name> --format process

  which prints credentials in the standard
  [credential_process JSON shape](https://docs.aws.amazon.com/cli/latest/topic/config-vars.html#sourcing-credentials-from-external-processes).
  The AWS CLI is responsible for refreshing the underlying token and
  for the on-disk cache layout; we never parse it directly.

  ## Requirements

    * AWS CLI ≥ 2.32.0 on `PATH` at runtime.

  ## Test override

  The synthesized command can be overridden via the
  `:export_credentials_command` opt for tests that don't want to depend
  on a real `aws` binary.
  """

  alias AwsSDK.Credentials.ProcessCreds
  alias AwsSDK.Credentials.Profile

  @doc false
  def resolve(opts) do
    profile_name = opts[:profile] || Profile.default()

    case Profile.load(profile_name, opts) do
      nil ->
        :skip

      profile ->
        case profile["login_session"] do
          v when is_binary(v) and v !== "" ->
            ProcessCreds.run(command(profile_name, opts), :login_session)

          _ ->
            :skip
        end
    end
  end

  defp command(profile_name, opts) do
    opts[:export_credentials_command] ||
      "aws configure export-credentials --profile #{profile_name} --format process"
  end
end
