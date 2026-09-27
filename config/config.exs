import Config

config :ex_utils, ExUtils.Strings,
  to_existing_atom: false,
  strict: false

# The credential and region source chains live in `AwsSDK.Config`'s module
# attributes; restating them here only risks the two drifting apart.
config :aws_sdk, sandbox: [enabled: false]
