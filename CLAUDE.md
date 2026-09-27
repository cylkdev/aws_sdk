# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
mix compile          # compile (warnings-as-errors in non-test envs)
mix test             # run all tests
mix test <file>      # run a single test file, e.g. mix test test/aws_sdk/s3/sandbox_test.exs
mix format           # format code
mix docs             # generate documentation
```

## Architecture

This library wraps AWS services (S3, EventBridge, CloudWatch Logs, IAM, STS, IAM Identity Center, Organizations) with consistent error handling, response deserialization, and sandbox support for testing.

### Service modules

Each service (`AwsSDK.S3`, `AwsSDK.EventBridge`, `AwsSDK.Logs`, `AwsSDK.IAM`, `AwsSDK.STS`, `AwsSDK.IdentityCenter`, `AwsSDK.Organizations`) follows the same structure:

- **Every input AWS requires for an operation is a positional argument.** `opts` (always last, always `\\ []`) carries only optional inputs plus credentials, region, endpoint overrides, and the sandbox flag. Requiredness is enforced by pattern match / guard on the function head (`when is_binary(arn)`), never by a runtime `require_opts!`-style check on the keyword list. When AWS requires *one of* two mutually exclusive inputs, expose two distinct named functions rather than one polymorphic head — e.g. `AwsSDK.ElasticLoadBalancingV2.describe_rules/2` (by listener ARN) vs `describe_rules_by_arns/2` (by rule ARNs), which send different wire params.
- Public functions check `sandbox?/1` first; if true, delegate to the `Sandbox` module
- Otherwise call `do_*` private functions, each an explicit pipeline: `with {:ok, op} <- build_operation(...), {:ok, %{body: body}} <- Client.request(op) do ...` — no per-module dispatch or response-mapping helpers
- Every service's `Client` module is a thin wrapper over `AwsSDK.Client`, the shared dispatcher that owns SigV4 signing, HTTP dispatch (`AwsSDK.HTTP`), credential/endpoint/sandbox resolution, and status-code branching. Per-service clients contribute only the protocol-specific pieces: body encoding (JSON / form-urlencoded / passthrough), request headers (X-Amz-Target for JSON 1.1; Action+Version for Query; per-operation for REST/XML), and URL composition (only S3 needs custom addressing). There is no ExAws integration.
- Wire protocols per service (these are AWS's protocols, not this library's choice — see each module's `@moduledoc` for the authoritative botocore model reference):
  - JSON 1.1: `AwsSDK.EventBridge`, `AwsSDK.Logs`, `AwsSDK.IdentityCenter` (both `sso-admin` and `identitystore`), `AwsSDK.Organizations`
  - Query (form-urlencoded request / XML response): `AwsSDK.IAM`, `AwsSDK.STS` (the internal `AwsSDK.Credentials.Providers.AssumeRole` provider routes its `AssumeRole` call through `AwsSDK.STS.assume_role/4` with pre-resolved source credentials), `AwsSDK.EC2`, `AwsSDK.AutoScaling`, `AwsSDK.ElasticLoadBalancingV2`. Note `AwsSDK.EC2` builds params with `put_member_list/3` + `put_filters/2` and parses inline, while `AwsSDK.AutoScaling` and `AwsSDK.ElasticLoadBalancingV2` share a recursive `flatten_query/1` and extracted `parse_*/1` functions — match the conventions of the module you are editing.
  - REST/XML: `AwsSDK.S3` (virtual-hosted addressing, per-operation response shapes, query-string presigning, streaming bodies)
  - XPath extraction for XML services happens in the service module via `SweetXml`. AWS exposes no JSON alternative for S3, IAM, or STS, so the XML handling is required.
- `AwsSDK.IdentityCenter` covers two sub-services (`sso-admin` and `identitystore`) through one client. `AwsSDK.Organizations` and `AwsSDK.IAM` are global services pinned to `us-east-1` for SigV4 signing.
- `AwsSDK.S3` is the only service with presigned URLs and streaming request/response bodies, backed by `AwsSDK.Signer.sign_query/5` / `presign_post_policy/4` and `AwsSDK.HTTP.stream_upload/5` / `stream_download/3`.

### Sandbox pattern

Each service has a `Sandbox` module backed by `SandboxRegistry` (optional dep, `:dev`/`:test` only). Responses are stored as lists of functions keyed by test PID. Sandbox functions support variable arity: `fn -> result end`, `fn key -> result end`, etc. The registry lookup key is the operation's first positional argument (so `set_*_responses` takes `{key_or_regex, fun}` tuples); operations with no required input key off `"*"` and accept a bare `fn`.

Activate with `sandbox: [enabled: true]` on any per-call opts (or set `config :aws_sdk, :sandbox, enabled: true`). When enabled, the public function delegates to the service's `Sandbox` module instead of making an HTTP call. There is no other sandbox mode.

`test/test_helper.exs` starts the sandboxes and `AwsSDK.Counter` (ETS-based call counter for test assertions).

### Response fidelity (non-negotiable)

**Parsers extract fields. They do not redesign the response.** A caller who knows the AWS API reference for an operation must be able to predict the returned map without reading this library's source. Concretely, every parser satisfies all of:

1. **Nesting preserved.** Every AWS sub-structure is a nested map. No prefix-flattening — `<placement><groupName>` is `placement: %{group_name: ...}`, never `placement_group_name:`.
2. **Names preserved.** Each key is the `snake_case` of the AWS member name and nothing else. No renaming (`<ipAddress>` is `:ip_address`, not `:public_ip_address`), no synthesized keys.
3. **Lists preserved.** `<xxxSet><item>...</item></xxxSet>` emits `xxx_set: [%{...}]` — the `Set` suffix is part of the member name and is kept; `<item>` is the list element, not a key. A `<entry><key/><value/></entry>` map-encoding stays a list of `%{key:, value:}`.
4. **Nothing dropped.** Every documented member is parsed, including `next_token` and other pagination fields. No hand-picked field subsets, no `fn _ -> {:ok, %{}} end` callbacks that discard the body.
5. **Envelope dropped.** The outer `<XxxResponse>`/`<XxxResult>` wrapper and the `RequestId` metadata layer are not surfaced. This is the only exception to rule 4.

Leaf-value **type coercion is expected**: cast numeric members to integers, booleans to booleans, and timestamps to `DateTime` per the AWS model — that changes values, not shape. `AwsSDK.STS` parsing `Expiration` into a `DateTime` and `AwsSDK.IdentityCenter` JSON-decoding the `inline_policy` string are both this, not reshaping.

For XML services, nest with an anchored keyword block and an optional (`o`) anchor, so an absent sub-structure is `nil` rather than a map of empty strings:

```elixir
placement: [~x"./placement"o, group_name: ~x"./groupName/text()"os, tenancy: ~x"./tenancy/text()"os]
```

Always anchor selectors to their result element (`~x"//ListPartsResult/Part"l`, not `~x"//Part"l`) — S3 responses in particular can carry an `<Error>` body on a 200.

`test/aws_sdk/conformance_test.exs` parses real XML fixtures and is where this rule is enforced. The sandbox tests assert against fixtures they register themselves, so they prove nothing about a parser; add conformance cases there instead.

### Serialization

Response deserialization is delegated to `ExUtils.Serializer.deserialize/1` (from the `:ex_utils` git dep), which recursively transforms map keys to snake_case atoms. `ExUtils.Strings` is configured with `to_existing_atom: false, strict: false` in `config/config.exs`, which disables atom-safety so unknown response keys are converted via `String.to_atom/1` rather than `String.to_existing_atom/1`. This matches the previous `AwsSDK.Serializer` behavior; tightening it would require an explicit `:allowed_keys` allowlist.

### Error handling

`AwsSDK.Error` delegates to the `ErrorMessage` library. `AwsSDK.Client.request/1` owns the status-code contract: 3xx → `bad_request`, HTTP 4xx → `not_found`, 5xx → `service_unavailable`, other failures → `internal_server_error`; HTTP failures carry the numeric status in the error details (`details.status`). The adapter is configurable via `config :aws_sdk, :error_message_adapter`.

### Configuration

`AwsSDK.Config` resolves each key from per-call opts, then the application environment (`:aws_sdk`), then a built-in source chain. Key config keys: `:region`, `:access_key_id`, `:secret_access_key`, `:sandbox` (a keyword list with `:enabled`).

Passing `profile: "name"` in per-call opts resolves every credential key and the region from that named shared-config profile, skipping the built-in chains entirely — so nothing is read from the system or application environment. Precedence is **explicit key opt > `:profile` > app env > built-in defaults**.

### S3 specifics

- `AwsSDK.S3.Multipart` manages multipart uploads with configurable `max_size` (aborts if exceeded)
- `AwsSDK.S3.XMLParser` parses S3 notification XML configs using SweetXml
- `AwsSDK.S3.Sandbox` supports bucket-scoped responses using exact strings or regex patterns for bucket matching
