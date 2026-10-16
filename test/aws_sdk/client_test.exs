defmodule AwsSDK.ClientTest do
  use ExUnit.Case, async: true

  alias AwsSDK.Client

  describe "error_message/3" do
    test "an EC2 NotFound code at status 400 is not_found" do
      response =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Response><Errors><Error><Code>InvalidVpcID.NotFound</Code><Message>The vpc ID 'vpc-00000000000000000' does not exist</Message></Error></Errors><RequestID>aa457d80-fbc9-47ec-9a7a-02525d33ed7a</RequestID></Response>"

      assert %ErrorMessage{
               code: :not_found,
               message: "resource not found.",
               details: %{status: 400, response: response, headers: []}
             } === Client.error_message(400, response, [])
    end

    test "a malformed id is bad_request" do
      response =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Response><Errors><Error><Code>InvalidGroupId.Malformed</Code><Message>Invalid id: \"sg-00000000000000000\"</Message></Error></Errors><RequestID>e1c788a5-8080-4562-9aa8-9b2c912ca97d</RequestID></Response>"

      assert %ErrorMessage{
               code: :bad_request,
               message: "bad request.",
               details: %{status: 400, response: response, headers: []}
             } === Client.error_message(400, response, [])
    end

    test "a JSON ValidationException is bad_request" do
      response =
        "{\"__type\":\"ValidationException\",\"message\":\"1 validation error detected: Value of the input at 'certificateStatuses' failed to satisfy constraint: Member must satisfy constraint: [Member must satisfy enum value set: [VALIDATION_TIMED_OUT, PENDING_VALIDATION, EXPIRED, INACTIVE, ISSUED, FAILED, REVOKED], Member must not be null]\"}"

      assert %ErrorMessage{
               code: :bad_request,
               message: "bad request.",
               details: %{status: 400, response: response, headers: []}
             } === Client.error_message(400, response, [])
    end

    test "an empty 404 is not_found" do
      assert %ErrorMessage{
               code: :not_found,
               message: "resource not found.",
               details: %{status: 404, response: "", headers: []}
             } === Client.error_message(404, "", [])
    end

    test "a BucketAlreadyExists code is conflict" do
      response =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Error><Code>BucketAlreadyExists</Code><Message>The requested bucket name is not available. The bucket namespace is shared by all users of the system. Please select a different name and try again.</Message><BucketName>test</BucketName><RequestId>T02HMJYS8MK6S7Q6</RequestId><HostId>qsRZ7YbNTqy9FZ+Wtu1mGwxfwI4nAo+FSk9TBR4QnniE31kZu9r9ciFZWr92tIY+cYBB7AwEhxE=</HostId></Error>"

      assert %ErrorMessage{
               code: :conflict,
               message: "conflict.",
               details: %{status: 409, response: response, headers: []}
             } === Client.error_message(409, response, [])
    end

    test "an AccessDenied code is forbidden" do
      response =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Error><Code>AccessDenied</Code><Message>User: arn:aws:sts::226147735359:assumed-role/AccountFullAccessRole/74c8b468-b061-707f-0c68-08d3d7b7676f is not authorized to perform: s3:CreateBucket on resource: \"arn:aws:s3:::mcp-proto-tfstate-226147735359\" with an explicit deny in a service control policy: arn:aws:organizations::494118670414:policy/o-ea45sie9yi/service_control_policy/p-2tdopezz</Message><RequestId>3RZKWWQ93ZN1AGZP</RequestId><HostId>KG/YixSuM2JtnqnuCXe50f0sCCke3OaUM7lQQcJ+BHHq9n93V9HVf20Bhc198yYEE2KLwcHzHZ4=</HostId></Error>"

      assert %ErrorMessage{
               code: :forbidden,
               message: "forbidden.",
               details: %{status: 403, response: response, headers: []}
             } === Client.error_message(403, response, [])
    end
  end
end
