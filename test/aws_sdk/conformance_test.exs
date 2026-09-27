defmodule AwsSDK.ConformanceTest do
  @moduledoc """
  Regression tests for the conformance defects found by auditing this library
  against the live AWS API references.

  Everything here is a pure function, so these assert on the exact bytes the
  library would put on the wire without standing up a transport.
  """

  use ExUnit.Case, async: true

  test "a caller-supplied host is signed once, not twice" do
    headers =
      AwsSDK.Signer.sign(
        :put,
        "https://bucket.s3.amazonaws.com/k",
        [{"host", "bucket.s3.amazonaws.com"}, {"content-type", "text/plain"}],
        "body",
        %{
          access_key_id: "AK",
          secret_access_key: "SK",
          region: "us-east-1",
          service: "s3",
          now: DateTime.utc_now()
        }
      )

    authorization = headers |> Enum.find(fn {k, _} -> k == "authorization" end) |> elem(1)
    signed = Regex.run(~r/SignedHeaders=([^,]+)/, authorization) |> Enum.at(1)

    assert Enum.count(String.split(signed, ";"), &(&1 == "host")) == 1
    assert Enum.count(headers, fn {k, _} -> k == "host" end) == 1
  end

  test "a caller-supplied x-amz-date is signed once, not twice" do
    headers =
      AwsSDK.Signer.sign(
        :get,
        "https://bucket.s3.amazonaws.com/k",
        [{"x-amz-date", "19700101T000000Z"}],
        "",
        %{
          access_key_id: "AK",
          secret_access_key: "SK",
          region: "us-east-1",
          service: "s3",
          now: DateTime.utc_now()
        }
      )

    authorization = headers |> Enum.find(fn {k, _} -> k == "authorization" end) |> elem(1)
    signed = Regex.run(~r/SignedHeaders=([^,]+)/, authorization) |> Enum.at(1)

    assert Enum.count(String.split(signed, ";"), &(&1 == "x-amz-date")) == 1
    assert Enum.count(headers, fn {k, _} -> k == "x-amz-date" end) == 1
  end

  test "put_bucket_encryption emits a real SSEAlgorithm when none is given" do
    xml = AwsSDK.S3.XMLBuilder.build_bucket_encryption([])

    assert xml =~ "<SSEAlgorithm>AES256</SSEAlgorithm>"
    refute xml =~ "<SSEAlgorithm></SSEAlgorithm>"
  end

  test "a lifecycle rule without :status defaults to Enabled instead of raising" do
    xml = AwsSDK.S3.XMLBuilder.build_lifecycle_configuration([%{id: "r", expiration: %{days: 1}}])

    assert xml =~ "<Status>Enabled</Status>"
  end

  test "put_public_access_block emits only the flags supplied" do
    xml = AwsSDK.S3.XMLBuilder.build_public_access_block(block_public_acls: true)

    assert xml =~ "<BlockPublicAcls>true</BlockPublicAcls>"
    refute xml =~ "IgnorePublicAcls"
    refute xml =~ "BlockPublicPolicy"
    refute xml =~ "RestrictPublicBuckets"
  end

  test "a 200 response carrying an Error body is not reported as success" do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Error><Code>InternalError</Code><Message>We encountered an internal error.</Message><RequestId>abc</RequestId></Error>
    """

    assert {:error, %ErrorMessage{details: details}} =
             AwsSDK.S3.XMLParser.parse_complete_multipart(xml)

    assert details.code == "InternalError"

    assert {:error, %ErrorMessage{}} = AwsSDK.S3.XMLParser.parse_copy_object_result(xml)
  end

  test "a successful CompleteMultipartUpload body still parses" do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <CompleteMultipartUploadResult><Location>https://x/k</Location><Bucket>b</Bucket><Key>k</Key><ETag>"e"</ETag></CompleteMultipartUploadResult>
    """

    assert %{bucket: "b", key: "k"} = AwsSDK.S3.XMLParser.parse_complete_multipart(xml)
  end

  test "an ini value containing # is not truncated" do
    parsed =
      AwsSDK.Credentials.INI.parse("""
      [p]
      secret = abc#def
      url = https://example.com/x#fragment
      commented = value # trailing comment
      """)

    assert parsed["p"]["secret"] == "abc#def"
    assert parsed["p"]["url"] == "https://example.com/x#fragment"
    assert parsed["p"]["commented"] == "value"
  end

  test "a whole-line ini comment is still ignored" do
    parsed =
      AwsSDK.Credentials.INI.parse("""
      [p]
      # this line is a comment
      key = value
      """)

    assert parsed["p"] == %{"key" => "value"}
  end

  test "Organizations ignores a caller region and uses the global endpoint" do
    {:ok, op} =
      AwsSDK.Organizations.build_operation("ListRoots", %{},
        access_key_id: "AK",
        secret_access_key: "SK",
        region: "eu-west-1"
      )

    assert op.url == "https://organizations.us-east-1.amazonaws.com/"
    assert op.region == "us-east-1"
  end

  test "Organizations stays inside the GovCloud partition" do
    {:ok, op} =
      AwsSDK.Organizations.build_operation("ListRoots", %{},
        access_key_id: "AK",
        secret_access_key: "SK",
        region: "us-gov-east-1"
      )

    assert op.url == "https://organizations.us-gov-west-1.amazonaws.com/"
    assert op.region == "us-gov-west-1"
  end

  test "presigned POST form fields keep their literal AWS names" do
    {:ok, result} =
      AwsSDK.S3.presign_post("b", "k.txt",
        access_key_id: "AK",
        secret_access_key: "SK",
        region: "us-east-1"
      )

    keys = Map.keys(result.fields)

    assert "policy" in keys
    assert "x-amz-algorithm" in keys
    assert "x-amz-credential" in keys
    assert "x-amz-signature" in keys
    refute Enum.any?(keys, &is_atom/1)
  end

  test "an S3 object key with reserved characters signs the path it sends" do
    {:ok, config} =
      AwsSDK.S3.resolve_config(
        access_key_id: "AK",
        secret_access_key: "SK",
        region: "us-east-1"
      )

    url = AwsSDK.S3.build_url(config, "bucket", "my file+a:b#c.txt", %{})

    # encode_key/1 applies AWS's UriEncode, so the signer can sign the path
    # verbatim and still match the wire.
    assert URI.parse(url).path == "/my%20file%2Ba%3Ab%23c.txt"
  end

  test "target health surfaces the reason code that distinguishes ELB faults from target faults" do
    xml = """
    <DescribeTargetHealthResponse><DescribeTargetHealthResult><TargetHealthDescriptions>
    <member><Target><Id>i-abc</Id><Port>80</Port><AvailabilityZone>us-east-1a</AvailabilityZone></Target>
    <HealthCheckPort>80</HealthCheckPort>
    <TargetHealth><State>unhealthy</State><Reason>Elb.InternalError</Reason>
    <Description>Health checks failed due to an internal error</Description></TargetHealth></member>
    </TargetHealthDescriptions></DescribeTargetHealthResult></DescribeTargetHealthResponse>
    """

    %{target_health_descriptions: [target]} =
      AwsSDK.ElasticLoadBalancingV2.parse_describe_target_health(xml)

    assert target.target_health.state == "unhealthy"
    assert target.target_health.reason == "Elb.InternalError"
    assert target.target_health.description == "Health checks failed due to an internal error"
    assert target.target.availability_zone == "us-east-1a"
    assert target.target.id == "i-abc"
    assert target.health_check_port == "80"

    # TargetHealth and AdministrativeOverride both carry State/Reason/Description;
    # flattening either onto the parent would collide them.
    refute Map.has_key?(target, :state)
  end

  test "a target group health check port keeps its non-numeric value" do
    xml = """
    <DescribeTargetGroupsResponse><DescribeTargetGroupsResult><TargetGroups><member>
    <TargetGroupArn>arn:tg/1</TargetGroupArn><TargetGroupName>web</TargetGroupName>
    <HealthCheckPort>traffic-port</HealthCheckPort><HealthCheckPath>/health</HealthCheckPath>
    <Matcher><HttpCode>200</HttpCode></Matcher>
    <LoadBalancerArns><member>arn:lb/1</member></LoadBalancerArns>
    </member></TargetGroups></DescribeTargetGroupsResult></DescribeTargetGroupsResponse>
    """

    %{target_groups: [group]} = AwsSDK.ElasticLoadBalancingV2.parse_describe_target_groups(xml)

    # HealthCheckPort is documented as a String; "traffic-port" is a legal value.
    assert group.health_check_port == "traffic-port"
    assert group.health_check_path == "/health"
    assert group.matcher.http_code == "200"
    assert group.load_balancer_arns == ["arn:lb/1"]
  end

  test "the default rule's priority stays the literal string \"default\"" do
    xml = """
    <DescribeRulesResponse><DescribeRulesResult><Rules>
    <member><RuleArn>arn:rule/def</RuleArn><Priority>default</Priority><IsDefault>true</IsDefault>
    <Conditions /><Actions><member><Type>forward</Type></member></Actions></member>
    </Rules></DescribeRulesResult></DescribeRulesResponse>
    """

    %{rules: [rule]} = AwsSDK.ElasticLoadBalancingV2.parse_describe_rules(xml)

    assert rule.priority == "default"
  end

  test "a query-string condition parses key/value pairs, not bare strings" do
    xml = """
    <DescribeRulesResponse><DescribeRulesResult><Rules><member>
    <RuleArn>arn:rule/1</RuleArn><Priority>10</Priority><IsDefault>false</IsDefault>
    <Conditions><member><Field>query-string</Field><QueryStringConfig><Values>
    <member><Key>ver</Key><Value>2</Value></member>
    </Values></QueryStringConfig></member></Conditions>
    <Actions><member><Type>redirect</Type><RedirectConfig>
    <StatusCode>HTTP_301</StatusCode><Port>443</Port></RedirectConfig></member></Actions>
    </member></Rules></DescribeRulesResult></DescribeRulesResponse>
    """

    %{rules: [rule]} = AwsSDK.ElasticLoadBalancingV2.parse_describe_rules(xml)
    [condition] = rule.conditions
    [action] = rule.actions

    assert condition.query_string_config.values == [%{key: "ver", value: "2"}]
    # RedirectConfig.Port is documented as a String, not an Integer.
    assert action.redirect_config.port == "443"
    assert action.redirect_config.status_code == "HTTP_301"
  end

  test "a forward action keeps its ForwardConfig whole rather than half-flattened" do
    xml = """
    <DescribeRulesResponse><DescribeRulesResult><Rules><member>
    <RuleArn>arn:rule/1</RuleArn><Priority>10</Priority><IsDefault>false</IsDefault>
    <Conditions><member><Field>host-header</Field>
    <HostHeaderConfig><Values><member>a.example.com</member></Values></HostHeaderConfig>
    </member></Conditions>
    <Actions><member><Type>forward</Type><ForwardConfig>
    <TargetGroups><member><TargetGroupArn>arn:tg/1</TargetGroupArn><Weight>90</Weight></member>
    <member><TargetGroupArn>arn:tg/2</TargetGroupArn><Weight>10</Weight></member></TargetGroups>
    <TargetGroupStickinessConfig><Enabled>true</Enabled><DurationSeconds>3600</DurationSeconds>
    </TargetGroupStickinessConfig></ForwardConfig></member></Actions>
    </member></Rules></DescribeRulesResult></DescribeRulesResponse>
    """

    %{rules: [rule]} = AwsSDK.ElasticLoadBalancingV2.parse_describe_rules(xml)
    [condition] = rule.conditions
    [action] = rule.actions

    assert condition.host_header_config.values == ["a.example.com"]
    # Which typed config AWS populated is readable from the response itself.
    assert condition.path_pattern_config == nil

    assert action.forward_config.target_groups == [
             %{target_group_arn: "arn:tg/1", weight: 90},
             %{target_group_arn: "arn:tg/2", weight: 10}
           ]

    assert action.forward_config.target_group_stickiness_config.duration_seconds == 3600
    refute Map.has_key?(action, :target_groups)
  end

  test "STS AssumeRole surfaces the assumed role identity, not just credentials" do
    xml = """
    <AssumeRoleResponse><AssumeRoleResult>
    <Credentials><AccessKeyId>AK</AccessKeyId><SecretAccessKey>SK</SecretAccessKey>
    <SessionToken>ST</SessionToken><Expiration>2030-01-01T00:00:00Z</Expiration></Credentials>
    <AssumedRoleUser><Arn>arn:aws:sts::1:assumed-role/r/s</Arn>
    <AssumedRoleId>AROA:s</AssumedRoleId></AssumedRoleUser>
    <PackedPolicySize>6</PackedPolicySize>
    </AssumeRoleResult></AssumeRoleResponse>
    """

    {:ok, creds} = AwsSDK.STS.parse_assume_role_for_test(xml)

    assert creds.assumed_role_user.arn == "arn:aws:sts::1:assumed-role/r/s"
    assert creds.assumed_role_user.assumed_role_id == "AROA:s"
    assert creds.packed_policy_size == 6

    # Credentials is a structure on the wire, so it stays one here.
    assert creds.credentials.access_key_id == "AK"
    assert creds.credentials.session_token == "ST"
    assert %DateTime{} = creds.credentials.expiration
    refute Map.has_key?(creds, :access_key_id)
  end

  test "an S3 notification configuration parses queue and lambda targets, not just EventBridge" do
    xml = """
    <NotificationConfiguration>
    <QueueConfiguration><Id>q1</Id><Queue>arn:aws:sqs:us-east-1:1:q</Queue>
    <Event>s3:ObjectCreated:*</Event>
    <Filter><S3Key><FilterRule><Name>prefix</Name><Value>logs/</Value></FilterRule></S3Key></Filter>
    </QueueConfiguration>
    <CloudFunctionConfiguration><Id>f1</Id>
    <CloudFunction>arn:aws:lambda:us-east-1:1:function:f</CloudFunction>
    <Event>s3:ObjectRemoved:*</Event></CloudFunctionConfiguration>
    <EventBridgeConfiguration></EventBridgeConfiguration>
    </NotificationConfiguration>
    """

    parsed = AwsSDK.S3.XMLParser.parse_notification_configuration(xml)

    # EventBridgeConfiguration has no members, so presence is the payload.
    assert parsed.event_bridge_configuration == %{}
    assert [queue] = parsed.queue_configuration
    assert queue.queue == "arn:aws:sqs:us-east-1:1:q"
    assert queue.event == ["s3:ObjectCreated:*"]

    # Filter and S3Key are two real wrapper elements, not decoration.
    assert queue.filter.s3_key.filter_rule == [%{name: "prefix", value: "logs/"}]

    # The wire element is CloudFunctionConfiguration/CloudFunction, not the
    # model's LambdaFunctionConfiguration/LambdaFunctionArn.
    assert [fun] = parsed.cloud_function_configuration
    assert fun.cloud_function == "arn:aws:lambda:us-east-1:1:function:f"
  end

  test "LaunchTemplateData keeps every nested structure and repeated set" do
    xml = """
    <DescribeLaunchTemplateVersionsResponse><launchTemplateVersionSet><item>
    <launchTemplateId>lt-1</launchTemplateId><launchTemplateName>web</launchTemplateName>
    <versionNumber>3</versionNumber><defaultVersion>false</defaultVersion>
    <createTime>2026-01-01T00:00:00Z</createTime>
    <launchTemplateData>
    <imageId>ami-1</imageId><instanceType>t3.micro</instanceType><keyName>k</keyName>
    <userData>ZWNobyBoaQ==</userData>
    <securityGroupIdSet><item>sg-1</item><item>sg-2</item></securityGroupIdSet>
    <iamInstanceProfile><arn>arn:aws:iam::1:instance-profile/p</arn></iamInstanceProfile>
    <placement><availabilityZone>us-east-1a</availabilityZone><groupName>g</groupName>
    <tenancy>default</tenancy></placement>
    <metadataOptions><httpTokens>required</httpTokens>
    <httpPutResponseHopLimit>2</httpPutResponseHopLimit></metadataOptions>
    <instanceMarketOptions><marketType>spot</marketType>
    <spotOptions><maxPrice>0.02</maxPrice><spotInstanceType>one-time</spotInstanceType>
    </spotOptions></instanceMarketOptions>
    <blockDeviceMappingSet>
    <item><deviceName>/dev/xvda</deviceName>
    <ebs><volumeSize>30</volumeSize><volumeType>gp3</volumeType>
    <deleteOnTermination>true</deleteOnTermination></ebs></item>
    <item><deviceName>/dev/sdb</deviceName><virtualName>ephemeral0</virtualName></item>
    </blockDeviceMappingSet>
    <networkInterfaceSet><item><deviceIndex>0</deviceIndex><subnetId>subnet-1</subnetId>
    <associatePublicIpAddress>true</associatePublicIpAddress>
    <groupSet><item>sg-1</item></groupSet></item></networkInterfaceSet>
    <tagSpecificationSet><item><resourceType>instance</resourceType>
    <tagSet><item><key>Name</key><value>web</value></item></tagSet></item></tagSpecificationSet>
    </launchTemplateData>
    </item></launchTemplateVersionSet></DescribeLaunchTemplateVersionsResponse>
    """

    parsed = AwsSDK.EC2.parse_describe_launch_template_versions_for_test(xml)

    assert [version] = parsed.launch_template_versions
    assert version.version_number == 3
    assert version.launch_template_id == "lt-1"

    data = version.launch_template_data
    assert data.image_id == "ami-1"

    # userData stays the base64 AWS stores; decoding it here would invent a
    # representation, and it is not always valid UTF-8.
    assert data.user_data == "ZWNobyBoaQ=="

    # Singleton sub-structures are maps, not prefixed scalars.
    assert data.placement.group_name == "g"
    assert data.placement.availability_zone == "us-east-1a"
    assert data.metadata_options.http_put_response_hop_limit == 2
    assert data.iam_instance_profile.arn == "arn:aws:iam::1:instance-profile/p"
    assert data.instance_market_options.spot_options.max_price == "0.02"
    refute Map.has_key?(data, :placement_group_name)

    # Repeated sets are lists -- the shape the old flattening could not express.
    assert data.security_group_id_set == ["sg-1", "sg-2"]

    assert [ebs_backed, instance_store] = data.block_device_mapping_set
    assert ebs_backed.ebs.volume_size == 30
    assert ebs_backed.ebs.volume_type == "gp3"
    assert instance_store.ebs == nil

    assert [eni] = data.network_interface_set
    assert eni.device_index == 0
    assert eni.group_set == ["sg-1"]

    # A TagSpecification nests its own tagSet.
    assert [%{resource_type: "instance", tag_set: [%{key: "Name", value: "web"}]}] =
             data.tag_specification_set
  end

  test "CreateLaunchTemplateVersion reads the new version and an optional warning" do
    xml_without_warning = """
    <CreateLaunchTemplateVersionResponse><launchTemplateVersion>
    <launchTemplateId>lt-1</launchTemplateId><launchTemplateName>web</launchTemplateName>
    <versionNumber>2</versionNumber><createTime>2026-01-01T00:00:00Z</createTime>
    <createdBy>arn:aws:iam::1:user/u</createdBy><defaultVersion>false</defaultVersion>
    <operator><managed>true</managed><principal>ec2.amazonaws.com</principal></operator>
    <launchTemplateData>
    <imageId>ami-1</imageId><instanceType>t3.micro</instanceType>
    </launchTemplateData>
    </launchTemplateVersion></CreateLaunchTemplateVersionResponse>
    """

    assert AwsSDK.EC2.parse_create_launch_template_version_for_test(xml_without_warning) == %{
             launch_template_version: %{
               launch_template_id: "lt-1",
               launch_template_name: "web",
               version_number: 2,
               version_description: "",
               create_time: "2026-01-01T00:00:00Z",
               created_by: "arn:aws:iam::1:user/u",
               default_version: "false",
               operator: %{managed: "true", principal: "ec2.amazonaws.com"},
               launch_template_data: %{
                 image_id: "ami-1",
                 instance_type: "t3.micro",
                 kernel_id: "",
                 ram_disk_id: "",
                 key_name: "",
                 user_data: "",
                 ebs_optimized: "",
                 disable_api_termination: "",
                 disable_api_stop: "",
                 instance_initiated_shutdown_behavior: "",
                 security_group_id_set: [],
                 security_group_set: [],
                 iam_instance_profile: nil,
                 monitoring: nil,
                 placement: nil,
                 cpu_options: nil,
                 metadata_options: nil,
                 enclave_options: nil,
                 hibernation_options: nil,
                 maintenance_options: nil,
                 private_dns_name_options: nil,
                 instance_market_options: nil,
                 credit_specification: nil,
                 capacity_reservation_specification: nil,
                 instance_requirements: nil,
                 block_device_mapping_set: [],
                 network_interface_set: [],
                 tag_specification_set: [],
                 license_set: [],
                 elastic_gpu_specification_set: []
               }
             },
             warning: nil
           }

    xml_with_warning = """
    <CreateLaunchTemplateVersionResponse><launchTemplateVersion>
    <launchTemplateId>lt-1</launchTemplateId><launchTemplateName>web</launchTemplateName>
    <versionNumber>2</versionNumber><createTime>2026-01-01T00:00:00Z</createTime>
    <createdBy>arn:aws:iam::1:user/u</createdBy><defaultVersion>false</defaultVersion>
    <launchTemplateData>
    <imageId>ami-1</imageId><instanceType>t3.micro</instanceType>
    </launchTemplateData>
    </launchTemplateVersion>
    <warning><errorSet><item><code>duplicateSecurityGroupId</code>
    <message>Security group sg-1 is duplicated.</message></item></errorSet></warning>
    </CreateLaunchTemplateVersionResponse>
    """

    parsed = AwsSDK.EC2.parse_create_launch_template_version_for_test(xml_with_warning)

    assert parsed.launch_template_version.launch_template_id == "lt-1"
    assert parsed.launch_template_version.version_number == 2

    assert parsed.warning == %{
             errors: [
               %{code: "duplicateSecurityGroupId", message: "Security group sg-1 is duplicated."}
             ]
           }

    assert {:ok, ^parsed} =
             AwsSDK.EC2.create_launch_template_version_result_for_test(xml_with_warning)
  end

  test "CreateLaunchTemplateVersion errors when the response carries no launchTemplateVersion" do
    xml = """
    <CreateLaunchTemplateVersionResponse>
      <requestId>59dbff89-35bd-4eac-99ed-be587EXAMPLE</requestId>
    </CreateLaunchTemplateVersionResponse>
    """

    assert {:error,
            {:unexpected_response, %{operation: "CreateLaunchTemplateVersion", body: ^xml}}} =
             AwsSDK.EC2.create_launch_template_version_result_for_test(xml)
  end

  test "ModifyLaunchTemplate reads the template whose default moved" do
    xml = """
    <ModifyLaunchTemplateResponse>
      <requestId>59dbff89-35bd-4eac-99ed-be587EXAMPLE</requestId>
      <launchTemplate>
        <launchTemplateId>lt-0a1b2c3d4e5f6a7b8</launchTemplateId>
        <launchTemplateName>deployd-cylk-web-dev-blue</launchTemplateName>
        <createTime>2026-08-10T17:29:15.000Z</createTime>
        <createdBy>arn:aws:sts::291093735280:assumed-role/deploy/session</createdBy>
        <defaultVersionNumber>3</defaultVersionNumber>
        <latestVersionNumber>7</latestVersionNumber>
        <operator>
          <managed>true</managed>
          <principal>ec2.amazonaws.com</principal>
        </operator>
        <tagSet>
          <item>
            <key>Colour</key>
            <value>blue</value>
          </item>
        </tagSet>
      </launchTemplate>
    </ModifyLaunchTemplateResponse>
    """

    assert %{
             launch_template: %{
               launch_template_id: "lt-0a1b2c3d4e5f6a7b8",
               launch_template_name: "deployd-cylk-web-dev-blue",
               create_time: "2026-08-10T17:29:15.000Z",
               created_by: "arn:aws:sts::291093735280:assumed-role/deploy/session",
               default_version_number: 3,
               latest_version_number: 7,
               operator: %{managed: "true", principal: "ec2.amazonaws.com"},
               tag_set: [%{key: "Colour", value: "blue"}]
             }
           } == AwsSDK.EC2.parse_modify_launch_template_for_test(xml)

    assert {:ok, %{launch_template: %{launch_template_id: "lt-0a1b2c3d4e5f6a7b8"}}} =
             AwsSDK.EC2.modify_launch_template_result_for_test(xml)
  end

  test "ModifyLaunchTemplate errors when the response carries no launchTemplate" do
    xml = """
    <ModifyLaunchTemplateResponse>
      <requestId>59dbff89-35bd-4eac-99ed-be587EXAMPLE</requestId>
    </ModifyLaunchTemplateResponse>
    """

    assert {:error, {:unexpected_response, %{operation: "ModifyLaunchTemplate", body: ^xml}}} =
             AwsSDK.EC2.modify_launch_template_result_for_test(xml)
  end

  test "ModifyLaunchTemplate builds LaunchTemplateId and SetDefaultVersion, with ClientToken only when given" do
    assert %{"LaunchTemplateId" => "lt-1", "SetDefaultVersion" => "3"} ==
             AwsSDK.EC2.modify_launch_template_params_for_test("lt-1", "3")

    assert %{
             "LaunchTemplateId" => "lt-1",
             "SetDefaultVersion" => "3",
             "ClientToken" => "token-1"
           } ==
             AwsSDK.EC2.modify_launch_template_params_for_test("lt-1", "3",
               client_token: "token-1"
             )
  end

  test "DeleteLaunchTemplateVersions reads a version in the successful set" do
    # Documented shape, from the API reference's example response -- no real
    # call to this operation has been made.
    xml = """
    <DeleteLaunchTemplateVersionsResponse xmlns="http://ec2.amazonaws.com/doc/2016-11-15/">
        <requestId>67fc746a-1b3f-467e-8583-7061cexample</requestId>
        <unsuccessfullyDeletedLaunchTemplateVersionSet/>
        <successfullyDeletedLaunchTemplateVersionSet>
            <item>
                <launchTemplateId>lt-0a20c965061f64abc</launchTemplateId>
                <launchTemplateName>MyLaunchTemplate</launchTemplateName>
                <versionNumber>3</versionNumber>
            </item>
        </successfullyDeletedLaunchTemplateVersionSet>
    </DeleteLaunchTemplateVersionsResponse>
    """

    assert %{
             successful: [
               %{
                 launch_template_id: "lt-0a20c965061f64abc",
                 launch_template_name: "MyLaunchTemplate",
                 version_number: 3
               }
             ],
             unsuccessful: []
           } == AwsSDK.EC2.parse_delete_launch_template_versions_for_test(xml)

    assert {:ok,
            %{
              launch_template_id: "lt-0a20c965061f64abc",
              launch_template_name: "MyLaunchTemplate",
              version_number: 3
            }} == AwsSDK.EC2.delete_launch_template_version_result_for_test(xml)
  end

  test "DeleteLaunchTemplateVersions reads a version in the unsuccessful set as an error, not a success" do
    # Documented shape, built from the API reference's
    # DeleteLaunchTemplateVersionsResponseErrorItem and ResponseError
    # structures -- no real call to this operation has been made.
    xml = """
    <DeleteLaunchTemplateVersionsResponse xmlns="http://ec2.amazonaws.com/doc/2016-11-15/">
        <requestId>67fc746a-1b3f-467e-8583-7061cexample</requestId>
        <unsuccessfullyDeletedLaunchTemplateVersionSet>
            <item>
                <launchTemplateId>lt-0a20c965061f64abc</launchTemplateId>
                <launchTemplateName>MyLaunchTemplate</launchTemplateName>
                <versionNumber>2</versionNumber>
                <responseError>
                    <code>launchTemplateVersionDoesNotExist</code>
                    <message>The specified launch template version does not exist.</message>
                </responseError>
            </item>
        </unsuccessfullyDeletedLaunchTemplateVersionSet>
        <successfullyDeletedLaunchTemplateVersionSet/>
    </DeleteLaunchTemplateVersionsResponse>
    """

    assert %{
             successful: [],
             unsuccessful: [
               %{
                 launch_template_id: "lt-0a20c965061f64abc",
                 launch_template_name: "MyLaunchTemplate",
                 version_number: 2,
                 response_error: %{
                   code: "launchTemplateVersionDoesNotExist",
                   message: "The specified launch template version does not exist."
                 }
               }
             ]
           } == AwsSDK.EC2.parse_delete_launch_template_versions_for_test(xml)

    assert {:error,
            {:launch_template_version_not_deleted,
             %{
               launch_template_id: "lt-0a20c965061f64abc",
               launch_template_name: "MyLaunchTemplate",
               version_number: 2,
               response_error: %{
                 code: "launchTemplateVersionDoesNotExist",
                 message: "The specified launch template version does not exist."
               }
             }}} == AwsSDK.EC2.delete_launch_template_version_result_for_test(xml)
  end

  test "DeleteLaunchTemplateVersions errors when the response carries the version in neither set" do
    xml = """
    <DeleteLaunchTemplateVersionsResponse xmlns="http://ec2.amazonaws.com/doc/2016-11-15/">
        <requestId>67fc746a-1b3f-467e-8583-7061cexample</requestId>
        <unsuccessfullyDeletedLaunchTemplateVersionSet/>
        <successfullyDeletedLaunchTemplateVersionSet/>
    </DeleteLaunchTemplateVersionsResponse>
    """

    assert {:error,
            {:unexpected_response, %{operation: "DeleteLaunchTemplateVersions", body: ^xml}}} =
             AwsSDK.EC2.delete_launch_template_version_result_for_test(xml)
  end

  test "DeleteLaunchTemplateVersions builds LaunchTemplateId and LaunchTemplateVersion.1" do
    assert %{"LaunchTemplateId" => "lt-1", "LaunchTemplateVersion.1" => "3"} ==
             AwsSDK.EC2.delete_launch_template_version_params_for_test("lt-1", "3")

    assert %{
             "LaunchTemplateId" => "lt-1",
             "LaunchTemplateVersion.1" => "3",
             "DryRun" => "true"
           } ==
             AwsSDK.EC2.delete_launch_template_version_params_for_test("lt-1", "3",
               dry_run: "true"
             )
  end

  test "CreateLaunchTemplateVersion builds LaunchTemplateData.<Member> and only-given options" do
    assert %{"LaunchTemplateId" => "lt-1", "LaunchTemplateData.ImageId" => "ami-1"} ==
             AwsSDK.EC2.create_launch_template_version_params_for_test("lt-1", %{
               "ImageId" => "ami-1"
             })

    assert %{
             "LaunchTemplateId" => "lt-1",
             "LaunchTemplateData.ImageId" => "ami-1",
             "LaunchTemplateData.InstanceType" => "t3.micro",
             "SourceVersion" => "2",
             "VersionDescription" => "blue",
             "ClientToken" => "token-1",
             "ResolveAlias" => "true"
           } ==
             AwsSDK.EC2.create_launch_template_version_params_for_test(
               "lt-1",
               %{"ImageId" => "ami-1", "InstanceType" => "t3.micro"},
               source_version: "2",
               version_description: "blue",
               client_token: "token-1",
               resolve_alias: "true"
             )
  end

  test "a launch template listing carries version pointers but no template data" do
    xml = """
    <DescribeLaunchTemplatesResponse><launchTemplates>
    <item><launchTemplateId>lt-1</launchTemplateId><launchTemplateName>web</launchTemplateName>
    <createTime>2026-01-01T00:00:00Z</createTime><createdBy>arn:aws:iam::1:user/u</createdBy>
    <defaultVersionNumber>1</defaultVersionNumber><latestVersionNumber>3</latestVersionNumber>
    <tagSet><item><key>env</key><value>prod</value></item></tagSet></item>
    </launchTemplates><nextToken>tok</nextToken></DescribeLaunchTemplatesResponse>
    """

    parsed = AwsSDK.EC2.parse_describe_launch_templates_for_test(xml)

    assert [template] = parsed.launch_templates
    assert template.default_version_number == 1
    assert template.latest_version_number == 3
    assert template.tag_set == [%{key: "env", value: "prod"}]
    assert parsed.next_token == "tok"

    # DescribeLaunchTemplates returns no configuration; that lives on a version.
    refute Map.has_key?(template, :launch_template_data)
  end

  test "ListObjectsV2 keeps CommonPrefix a structure and casts its integers" do
    xml = """
    <ListBucketResult><Name>b</Name><Prefix>logs/</Prefix><KeyCount>1</KeyCount>
    <MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated><Delimiter>/</Delimiter>
    <Contents><Key>logs/a.txt</Key><LastModified>2026-01-01T00:00:00Z</LastModified>
    <ETag>"e"</ETag><Size>42</Size><StorageClass>STANDARD</StorageClass>
    <Owner><ID>oid</ID><DisplayName>o</DisplayName></Owner></Contents>
    <CommonPrefixes><Prefix>logs/2026/</Prefix></CommonPrefixes>
    <CommonPrefixes><Prefix>logs/2025/</Prefix></CommonPrefixes>
    </ListBucketResult>
    """

    parsed = AwsSDK.S3.XMLParser.parse_list_objects(xml)

    # Each CommonPrefixes entry is a CommonPrefix structure with a Prefix
    # member, not a bare string.
    assert parsed.common_prefixes == [%{prefix: "logs/2026/"}, %{prefix: "logs/2025/"}]

    # KeyCount, MaxKeys and Size are Integers in the model.
    assert parsed.key_count == 1
    assert parsed.max_keys == 1000
    assert [%{size: 42, owner: %{id: "oid"}}] = parsed.contents
  end

  test "an IAM role keeps PermissionsBoundary and RoleLastUsed as structures" do
    xml = """
    <GetRoleResponse><GetRoleResult><Role>
    <RoleName>AdminRole</RoleName><RoleId>AROA1</RoleId>
    <Arn>arn:aws:iam::1:role/AdminRole</Arn><Path>/</Path>
    <CreateDate>2026-01-01T00:00:00Z</CreateDate><MaxSessionDuration>3600</MaxSessionDuration>
    <PermissionsBoundary>
    <PermissionsBoundaryArn>arn:aws:iam::1:policy/b</PermissionsBoundaryArn>
    <PermissionsBoundaryType>Policy</PermissionsBoundaryType></PermissionsBoundary>
    <RoleLastUsed><LastUsedDate>2026-02-01T00:00:00Z</LastUsedDate><Region>us-east-1</Region>
    </RoleLastUsed>
    <Tags><member><Key>team</Key><Value>infra</Value></member></Tags>
    </Role></GetRoleResult></GetRoleResponse>
    """

    role = AwsSDK.IAM.parse_role_for_test(xml)

    assert role.permissions_boundary.permissions_boundary_arn == "arn:aws:iam::1:policy/b"
    assert role.permissions_boundary.permissions_boundary_type == "Policy"

    # RoleLastUsed's members are LastUsedDate and Region; they were previously
    # hoisted onto the role AND prefix-renamed to role_last_used_*.
    assert role.role_last_used == %{last_used_date: "2026-02-01T00:00:00Z", region: "us-east-1"}
    refute Map.has_key?(role, :role_last_used_date)

    assert role.tags == [%{key: "team", value: "infra"}]
    assert role.max_session_duration == 3600
  end

  test "GetAccountSummary keeps SummaryMap's entry list" do
    xml = """
    <GetAccountSummaryResponse><GetAccountSummaryResult><SummaryMap>
    <entry><key>Users</key><value>3</value></entry>
    <entry><key>Groups</key><value>1</value></entry>
    </SummaryMap></GetAccountSummaryResult></GetAccountSummaryResponse>
    """

    assert %{summary_map: entries} = AwsSDK.IAM.parse_account_summary_for_test(xml)
    assert entries == [%{key: "Users", value: 3}, %{key: "Groups", value: 1}]
  end

  test "a MixedInstancesPolicy keeps both of the levels it used to collapse" do
    xml = """
    <DescribeAutoScalingGroupsResponse><DescribeAutoScalingGroupsResult><AutoScalingGroups>
    <member><AutoScalingGroupName>asg</AutoScalingGroupName><MinSize>1</MinSize><MaxSize>3</MaxSize>
    <DesiredCapacity>2</DesiredCapacity><DefaultCooldown>300</DefaultCooldown>
    <HealthCheckType>EC2</HealthCheckType><CreatedTime>2026-01-01T00:00:00Z</CreatedTime>
    <NewInstancesProtectedFromScaleIn>false</NewInstancesProtectedFromScaleIn>
    <MixedInstancesPolicy>
    <InstancesDistribution><OnDemandBaseCapacity>1</OnDemandBaseCapacity>
    <SpotAllocationStrategy>capacity-optimized</SpotAllocationStrategy>
    <SpotMaxPrice>0.05</SpotMaxPrice></InstancesDistribution>
    <LaunchTemplate>
    <LaunchTemplateSpecification><LaunchTemplateId>lt-1</LaunchTemplateId><Version>$Latest</Version>
    </LaunchTemplateSpecification>
    <Overrides><member><InstanceType>t3.small</InstanceType><WeightedCapacity>2</WeightedCapacity>
    </member></Overrides>
    </LaunchTemplate>
    </MixedInstancesPolicy>
    <Instances><member><InstanceId>i-1</InstanceId><InstanceType>t3.small</InstanceType>
    <AvailabilityZone>us-east-1a</AvailabilityZone><LifecycleState>InService</LifecycleState>
    <HealthStatus>Healthy</HealthStatus><LaunchConfigurationName />
    <ProtectedFromScaleIn>false</ProtectedFromScaleIn>
    <LaunchTemplate><LaunchTemplateId>lt-1</LaunchTemplateId><Version>3</Version></LaunchTemplate>
    </member></Instances>
    </member></AutoScalingGroups></DescribeAutoScalingGroupsResult></DescribeAutoScalingGroupsResponse>
    """

    %{auto_scaling_groups: [group]} =
      AwsSDK.AutoScaling.parse_describe_auto_scaling_groups_for_test(xml)

    policy = group.mixed_instances_policy

    # InstancesDistribution and LaunchTemplate/LaunchTemplateSpecification are
    # two separate levels; both used to be collapsed onto the policy.
    assert policy.instances_distribution.on_demand_base_capacity == 1
    assert policy.instances_distribution.spot_max_price == "0.05"
    assert policy.launch_template.launch_template_specification.launch_template_id == "lt-1"
    assert policy.launch_template.launch_template_specification.version == "$Latest"

    assert [%{instance_type: "t3.small", weighted_capacity: "2"}] =
             policy.launch_template.overrides

    refute Map.has_key?(policy, :launch_template_id)

    # An instance's LaunchTemplate is a LaunchTemplateSpecification, the same
    # shape the group-level :launch_template already kept nested.
    assert [instance] = group.instances

    assert instance.launch_template == %{
             launch_template_id: "lt-1",
             launch_template_name: "",
             version: "3"
           }
  end

  test "DescribeInstances mirrors AWS's nesting instead of flattening it" do
    xml = """
    <DescribeInstancesResponse><reservationSet><item>
    <reservationId>r-1</reservationId><ownerId>111</ownerId>
    <instancesSet><item>
    <instanceId>i-1</instanceId><imageId>ami-1</imageId><instanceType>t3.micro</instanceType>
    <privateIpAddress>10.0.0.5</privateIpAddress><ipAddress>1.2.3.4</ipAddress>
    <dnsName>ec2-1-2-3-4.compute.amazonaws.com</dnsName>
    <subnetId>subnet-1</subnetId><vpcId>vpc-1</vpcId><launchTime>2026-01-01T00:00:00Z</launchTime>
    <instanceState><code>16</code><name>running</name></instanceState>
    <placement><availabilityZone>us-east-1a</availabilityZone><groupName>g</groupName>
    <tenancy>default</tenancy></placement>
    <cpuOptions><coreCount>2</coreCount><threadsPerCore>1</threadsPerCore></cpuOptions>
    <metadataOptions><httpTokens>required</httpTokens><httpPutResponseHopLimit>2</httpPutResponseHopLimit>
    </metadataOptions>
    <iamInstanceProfile><arn>arn:aws:iam::111:instance-profile/p</arn><id>AIPA1</id></iamInstanceProfile>
    <blockDeviceMapping><item><deviceName>/dev/xvda</deviceName>
    <ebs><volumeId>vol-1</volumeId><status>attached</status></ebs></item></blockDeviceMapping>
    <networkInterfaceSet><item><networkInterfaceId>eni-1</networkInterfaceId>
    <association><publicIp>1.2.3.4</publicIp><ipOwnerId>amazon</ipOwnerId></association>
    <attachment><attachmentId>eni-attach-1</attachmentId><deviceIndex>0</deviceIndex></attachment>
    <groupSet><item><groupId>sg-9</groupId><groupName>eni-sg</groupName></item></groupSet>
    </item></networkInterfaceSet>
    <tagSet><item><key>Name</key><value>web</value></item></tagSet>
    <groupSet><item><groupId>sg-1</groupId><groupName>web</groupName></item></groupSet>
    </item></instancesSet>
    </item></reservationSet></DescribeInstancesResponse>
    """

    parsed = AwsSDK.EC2.parse_describe_instances_for_test(xml)

    assert [reservation] = parsed.reservation_set
    assert [instance] = reservation.instances_set

    # Sub-structures stay sub-structures.
    assert instance.instance_state == %{code: 16, name: "running"}
    assert instance.placement.group_name == "g"
    assert instance.placement.availability_zone == "us-east-1a"
    assert instance.cpu_options.core_count == 2
    assert instance.cpu_options.threads_per_core == 1
    assert instance.metadata_options.http_put_response_hop_limit == 2
    assert instance.iam_instance_profile.arn == "arn:aws:iam::111:instance-profile/p"

    # Member names are AWS's, not the library's.
    assert instance.ip_address == "1.2.3.4"
    assert instance.dns_name == "ec2-1-2-3-4.compute.amazonaws.com"
    refute Map.has_key?(instance, :public_ip_address)
    refute Map.has_key?(instance, :state)
    refute Map.has_key?(instance, :placement_group_name)

    # Nested lists keep their own sub-structures.
    assert [%{device_name: "/dev/xvda", ebs: ebs}] = instance.block_device_mapping
    assert ebs.volume_id == "vol-1"
    assert [eni] = instance.network_interface_set
    assert eni.association.public_ip == "1.2.3.4"
    assert eni.attachment.device_index == 0

    # `groupSet` resolves per level rather than being renamed differently at each.
    assert eni.group_set == [%{group_id: "sg-9", group_name: "eni-sg"}]
    assert instance.group_set == [%{group_id: "sg-1", group_name: "web"}]
    assert instance.tag_set == [%{key: "Name", value: "web"}]
  end

  test "an instance-store block device yields a nil :ebs rather than an empty-string snapshot" do
    xml = """
    <DescribeImagesResponse><imagesSet><item>
    <imageId>ami-1</imageId><name>n</name><imageState>available</imageState>
    <imageOwnerId>111</imageOwnerId><creationDate>2026-01-01T00:00:00Z</creationDate>
    <stateReason><code>c</code><message>m</message></stateReason>
    <blockDeviceMapping>
    <item><deviceName>/dev/xvda</deviceName><ebs><snapshotId>snap-1</snapshotId></ebs></item>
    <item><deviceName>/dev/sdb</deviceName><virtualName>ephemeral0</virtualName></item>
    </blockDeviceMapping>
    </item></imagesSet></DescribeImagesResponse>
    """

    assert %{images_set: [image]} = AwsSDK.EC2.parse_describe_images_for_test(xml)
    assert image.image_state == "available"
    assert image.state_reason == %{code: "c", message: "m"}

    assert [ebs_backed, instance_store] = image.block_device_mapping
    assert ebs_backed.ebs.snapshot_id == "snap-1"
    assert instance_store.ebs == nil
  end

  test "TerminateInstances keeps both states and integer state codes" do
    xml = """
    <TerminateInstancesResponse><instancesSet>
    <item><instanceId>i-1</instanceId>
    <currentState><code>32</code><name>shutting-down</name></currentState>
    <previousState><code>16</code><name>running</name></previousState></item>
    <item><instanceId>i-2</instanceId>
    <currentState><code>48</code><name>terminated</name></currentState>
    <previousState><code>64</code><name>stopping</name></previousState></item>
    </instancesSet></TerminateInstancesResponse>
    """

    parsed = AwsSDK.EC2.parse_terminate_instances_for_test(xml)

    assert [one, two] = parsed.instances_set
    assert one.instance_id == "i-1"
    assert one.current_state == %{code: 32, name: "shutting-down"}
    assert one.previous_state == %{code: 16, name: "running"}
    assert two.current_state.name == "terminated"
  end

  test "GetConsoleOutput decodes the base64 output and keeps the timestamp" do
    # "boot ok\n" base64-encoded, as AWS returns it on the wire.
    xml = """
    <GetConsoleOutputResponse>
    <instanceId>i-1</instanceId>
    <timestamp>2026-08-05T12:00:00.000Z</timestamp>
    <output>Ym9vdCBvawo=</output>
    </GetConsoleOutputResponse>
    """

    parsed = AwsSDK.EC2.parse_get_console_output_for_test(xml)

    assert parsed.instance_id == "i-1"
    assert parsed.timestamp == "2026-08-05T12:00:00.000Z"
    assert parsed.output == "boot ok\n"
  end

  test "GetConsoleOutput yields nil output when AWS omits it" do
    xml = "<GetConsoleOutputResponse><instanceId>i-1</instanceId></GetConsoleOutputResponse>"

    parsed = AwsSDK.EC2.parse_get_console_output_for_test(xml)

    assert parsed.output == nil
  end

  test "DescribeNetworkAcls keeps entries, associations, and the default flag" do
    xml = """
    <DescribeNetworkAclsResponse><networkAclSet><item>
    <networkAclId>acl-1</networkAclId><vpcId>vpc-1</vpcId>
    <default>true</default><ownerId>123456789012</ownerId>
    <entrySet>
    <item><ruleNumber>100</ruleNumber><protocol>6</protocol><ruleAction>allow</ruleAction>
    <egress>false</egress><cidrBlock>0.0.0.0/0</cidrBlock>
    <portRange><from>443</from><to>443</to></portRange></item>
    <item><ruleNumber>32767</ruleNumber><protocol>-1</protocol><ruleAction>deny</ruleAction>
    <egress>false</egress><cidrBlock>0.0.0.0/0</cidrBlock></item>
    </entrySet>
    <associationSet><item>
    <networkAclAssociationId>aclassoc-1</networkAclAssociationId>
    <networkAclId>acl-1</networkAclId><subnetId>subnet-1</subnetId>
    </item></associationSet>
    <tagSet><item><key>Name</key><value>main</value></item></tagSet>
    </item></networkAclSet>
    <nextToken>tok</nextToken></DescribeNetworkAclsResponse>
    """

    parsed = AwsSDK.EC2.parse_describe_network_acls_for_test(xml)

    assert [acl] = parsed.network_acl_set
    assert acl.network_acl_id == "acl-1"
    assert acl.default == true
    assert [https, deny_all] = acl.entry_set
    assert https.rule_number == 100
    assert https.egress == false
    assert https.port_range == %{from: 443, to: 443}
    # An entry without a portRange must yield nil, not a map of empty strings.
    assert deny_all.port_range == nil
    assert [assoc] = acl.association_set
    assert assoc.subnet_id == "subnet-1"
    assert acl.tag_set == [%{key: "Name", value: "main"}]
    assert parsed.next_token == "tok"
  end

  test "DescribeRouteTables keeps routes, associations, and propagating VGWs" do
    xml = """
    <DescribeRouteTablesResponse><routeTableSet><item>
    <routeTableId>rtb-1</routeTableId><vpcId>vpc-1</vpcId><ownerId>123456789012</ownerId>
    <routeSet>
    <item><destinationCidrBlock>10.0.0.0/16</destinationCidrBlock>
    <gatewayId>local</gatewayId><state>active</state><origin>CreateRouteTable</origin></item>
    <item><destinationCidrBlock>0.0.0.0/0</destinationCidrBlock>
    <natGatewayId>nat-1</natGatewayId><state>blackhole</state><origin>CreateRoute</origin></item>
    </routeSet>
    <associationSet><item>
    <routeTableAssociationId>rtbassoc-1</routeTableAssociationId>
    <routeTableId>rtb-1</routeTableId><subnetId>subnet-1</subnetId><main>false</main>
    <associationState><state>associated</state></associationState>
    </item></associationSet>
    <propagatingVgwSet><item><gatewayId>vgw-1</gatewayId></item></propagatingVgwSet>
    <tagSet><item><key>Name</key><value>private</value></item></tagSet>
    </item></routeTableSet></DescribeRouteTablesResponse>
    """

    parsed = AwsSDK.EC2.parse_describe_route_tables_for_test(xml)

    assert [table] = parsed.route_table_set
    assert table.route_table_id == "rtb-1"
    assert [local, nat] = table.route_set
    assert local.gateway_id == "local"
    assert nat.nat_gateway_id == "nat-1"
    assert nat.state == "blackhole"
    assert [assoc] = table.association_set
    assert assoc.main == false
    # The associationState element is present, so it is a map (not nil); its
    # absent statusMessage is "" the way every other optional scalar reads.
    assert assoc.association_state == %{state: "associated", status_message: ""}
    assert table.propagating_vgw_set == [%{gateway_id: "vgw-1"}]
    # Absent nextToken reads "" here, as it does in every EC2 parser.
    assert parsed.next_token == ""
  end

  test "DescribeKeyPairs keeps fingerprint, type, and tags" do
    xml = """
    <DescribeKeyPairsResponse><keySet><item>
    <keyPairId>key-1</keyPairId><keyName>deploy</keyName>
    <keyFingerprint>ab:cd</keyFingerprint><keyType>ed25519</keyType>
    <createTime>2026-01-01T00:00:00Z</createTime>
    <tagSet><item><key>Team</key><value>ops</value></item></tagSet>
    </item></keySet></DescribeKeyPairsResponse>
    """

    parsed = AwsSDK.EC2.parse_describe_key_pairs_for_test(xml)

    assert [key] = parsed.key_set
    assert key.key_pair_id == "key-1"
    assert key.key_name == "deploy"
    assert key.key_fingerprint == "ab:cd"
    assert key.key_type == "ed25519"
    assert key.create_time == "2026-01-01T00:00:00Z"
    assert key.tag_set == [%{key: "Team", value: "ops"}]
  end

  test "DeleteKeyPair keeps the return flag and the deleted key's id" do
    xml = """
    <DeleteKeyPairResponse><return>true</return><keyPairId>key-1</keyPairId></DeleteKeyPairResponse>
    """

    parsed = AwsSDK.EC2.parse_delete_key_pair_for_test(xml)

    assert parsed.return == true
    assert parsed.key_pair_id == "key-1"
  end

  test "DescribeSecurityGroupRules keeps rule granularity and referenced groups" do
    xml = """
    <DescribeSecurityGroupRulesResponse><securityGroupRuleSet>
    <item><securityGroupRuleId>sgr-1</securityGroupRuleId>
    <groupId>sg-1</groupId><groupOwnerId>123456789012</groupOwnerId>
    <isEgress>false</isEgress><ipProtocol>tcp</ipProtocol>
    <fromPort>443</fromPort><toPort>443</toPort>
    <cidrIpv4>0.0.0.0/0</cidrIpv4>
    <tagSet/></item>
    <item><securityGroupRuleId>sgr-2</securityGroupRuleId>
    <groupId>sg-1</groupId><isEgress>true</isEgress><ipProtocol>-1</ipProtocol>
    <fromPort>-1</fromPort><toPort>-1</toPort>
    <referencedGroupInfo><groupId>sg-2</groupId><userId>123456789012</userId></referencedGroupInfo>
    </item>
    </securityGroupRuleSet>
    <nextToken>tok</nextToken></DescribeSecurityGroupRulesResponse>
    """

    parsed = AwsSDK.EC2.parse_describe_security_group_rules_for_test(xml)

    assert [ingress, egress] = parsed.security_group_rule_set
    assert ingress.security_group_rule_id == "sgr-1"
    assert ingress.is_egress == false
    assert ingress.from_port == 443
    assert ingress.cidr_ipv4 == "0.0.0.0/0"
    assert ingress.referenced_group_info == nil
    assert egress.is_egress == true
    assert egress.referenced_group_info.group_id == "sg-2"
    assert parsed.next_token == "tok"
  end

  test "DescribeSnapshots keeps the full snapshot shape" do
    xml = """
    <DescribeSnapshotsResponse><snapshotSet><item>
    <snapshotId>snap-1</snapshotId><volumeId>vol-1</volumeId>
    <status>completed</status><startTime>2026-01-01T00:00:00Z</startTime>
    <progress>100%</progress><ownerId>123456789012</ownerId>
    <volumeSize>30</volumeSize><description>ami backing</description>
    <encrypted>false</encrypted><storageTier>standard</storageTier>
    <tagSet><item><key>Name</key><value>web</value></item></tagSet>
    </item></snapshotSet>
    <nextToken>tok</nextToken></DescribeSnapshotsResponse>
    """

    parsed = AwsSDK.EC2.parse_describe_snapshots_for_test(xml)

    assert [snap] = parsed.snapshot_set
    assert snap.snapshot_id == "snap-1"
    assert snap.volume_id == "vol-1"
    assert snap.status == "completed"
    assert snap.start_time == "2026-01-01T00:00:00Z"
    assert snap.volume_size == 30
    assert snap.encrypted == false
    assert snap.tag_set == [%{key: "Name", value: "web"}]
    assert parsed.next_token == "tok"
  end

  test "DescribeNetworkInterfaces keeps attachment, association, and groups" do
    xml = """
    <DescribeNetworkInterfacesResponse><networkInterfaceSet><item>
    <networkInterfaceId>eni-1</networkInterfaceId><subnetId>subnet-1</subnetId>
    <vpcId>vpc-1</vpcId><availabilityZone>us-east-1a</availabilityZone>
    <description>web eni</description><ownerId>123456789012</ownerId>
    <status>in-use</status><macAddress>0a:bb</macAddress>
    <privateIpAddress>10.0.1.5</privateIpAddress>
    <privateDnsName>ip-10-0-1-5.ec2.internal</privateDnsName>
    <sourceDestCheck>true</sourceDestCheck><interfaceType>interface</interfaceType>
    <requesterManaged>false</requesterManaged>
    <groupSet><item><groupId>sg-1</groupId><groupName>web</groupName></item></groupSet>
    <attachment><attachmentId>eni-attach-1</attachmentId><instanceId>i-1</instanceId>
    <instanceOwnerId>123456789012</instanceOwnerId><deviceIndex>0</deviceIndex>
    <status>attached</status><attachTime>2026-01-01T00:00:00Z</attachTime>
    <deleteOnTermination>true</deleteOnTermination></attachment>
    <association><publicIp>3.3.3.3</publicIp><publicDnsName>ec2-3-3-3-3.compute-1.amazonaws.com</publicDnsName>
    <ipOwnerId>amazon</ipOwnerId></association>
    <privateIpAddressesSet><item><privateIpAddress>10.0.1.5</privateIpAddress>
    <primary>true</primary></item></privateIpAddressesSet>
    <tagSet/>
    </item></networkInterfaceSet></DescribeNetworkInterfacesResponse>
    """

    parsed = AwsSDK.EC2.parse_describe_network_interfaces_for_test(xml)

    assert [eni] = parsed.network_interface_set
    assert eni.network_interface_id == "eni-1"
    assert eni.status == "in-use"
    assert eni.group_set == [%{group_id: "sg-1", group_name: "web"}]
    assert eni.attachment.instance_id == "i-1"
    assert eni.attachment.device_index == 0
    assert eni.association.public_ip == "3.3.3.3"
    assert [primary_ip] = eni.private_ip_addresses_set
    # `primary` is a nested boolean, left as the wire string per the module's
    # convention (only the named top-level flags are coerced).
    assert primary_ip.primary == "true"
    assert parsed.next_token == ""
  end

  test "DescribeNetworkInterfaces yields nil for a detached interface's attachment" do
    xml = """
    <DescribeNetworkInterfacesResponse><networkInterfaceSet><item>
    <networkInterfaceId>eni-2</networkInterfaceId><status>available</status>
    </item></networkInterfaceSet></DescribeNetworkInterfacesResponse>
    """

    parsed = AwsSDK.EC2.parse_describe_network_interfaces_for_test(xml)

    assert [eni] = parsed.network_interface_set
    assert eni.attachment == nil
    assert eni.association == nil
  end

  test "DescribeInstanceStatus keeps both status structures with details and events" do
    xml = """
    <DescribeInstanceStatusResponse><instanceStatusSet><item>
    <instanceId>i-1</instanceId><availabilityZone>us-east-1a</availabilityZone>
    <instanceState><code>16</code><name>running</name></instanceState>
    <systemStatus><status>ok</status>
    <details><item><name>reachability</name><status>passed</status></item></details>
    </systemStatus>
    <instanceStatus><status>impaired</status>
    <details><item><name>reachability</name><status>failed</status>
    <impairedSince>2026-08-05T11:00:00Z</impairedSince></item></details>
    </instanceStatus>
    <eventsSet><item><instanceEventId>event-1</instanceEventId>
    <code>system-reboot</code><description>scheduled reboot</description>
    <notBefore>2026-08-10T00:00:00Z</notBefore></item></eventsSet>
    </item></instanceStatusSet></DescribeInstanceStatusResponse>
    """

    parsed = AwsSDK.EC2.parse_describe_instance_status_for_test(xml)

    assert [status] = parsed.instance_status_set
    assert status.instance_id == "i-1"
    assert status.instance_state == %{code: 16, name: "running"}
    assert status.system_status.status == "ok"
    assert [sys_detail] = status.system_status.details
    assert sys_detail.status == "passed"
    assert status.instance_status.status == "impaired"
    assert [inst_detail] = status.instance_status.details
    assert inst_detail.impaired_since == "2026-08-05T11:00:00Z"
    assert [event] = status.events_set
    assert event.code == "system-reboot"
    assert parsed.next_token == ""
  end

  test "DescribeIamInstanceProfileAssociations keeps the nested profile" do
    xml = """
    <DescribeIamInstanceProfileAssociationsResponse><iamInstanceProfileAssociationSet>
    <item><associationId>iip-assoc-1</associationId><instanceId>i-1</instanceId>
    <iamInstanceProfile><arn>arn:aws:iam::1:instance-profile/web</arn><id>AIPA1</id></iamInstanceProfile>
    <state>associated</state><timestamp>2026-01-01T00:00:00Z</timestamp></item>
    </iamInstanceProfileAssociationSet>
    <nextToken>tok</nextToken></DescribeIamInstanceProfileAssociationsResponse>
    """

    parsed = AwsSDK.EC2.parse_describe_iam_instance_profile_associations_for_test(xml)

    assert [assoc] = parsed.iam_instance_profile_association_set
    assert assoc.association_id == "iip-assoc-1"
    assert assoc.instance_id == "i-1"

    assert assoc.iam_instance_profile == %{
             arn: "arn:aws:iam::1:instance-profile/web",
             id: "AIPA1"
           }

    assert assoc.state == "associated"
    assert parsed.next_token == "tok"
  end

  test "CreateNetworkInsightsPath keeps the full path shape" do
    xml = """
    <CreateNetworkInsightsPathResponse><networkInsightsPath>
    <networkInsightsPathId>nip-1</networkInsightsPathId>
    <networkInsightsPathArn>arn:aws:ec2:us-east-1:1:network-insights-path/nip-1</networkInsightsPathArn>
    <createdDate>2026-08-05T12:00:00Z</createdDate>
    <source>i-1</source><destination>i-2</destination>
    <sourceArn>arn:aws:ec2:us-east-1:1:instance/i-1</sourceArn>
    <destinationArn>arn:aws:ec2:us-east-1:1:instance/i-2</destinationArn>
    <protocol>tcp</protocol><destinationPort>443</destinationPort>
    <tagSet/></networkInsightsPath></CreateNetworkInsightsPathResponse>
    """

    parsed = AwsSDK.EC2.parse_create_network_insights_path_for_test(xml)

    path = parsed.network_insights_path
    assert path.network_insights_path_id == "nip-1"
    assert path.source == "i-1"
    assert path.destination == "i-2"
    assert path.protocol == "tcp"
    assert path.destination_port == 443
  end

  test "StartNetworkInsightsAnalysis keeps the initial analysis state" do
    xml = """
    <StartNetworkInsightsAnalysisResponse><networkInsightsAnalysis>
    <networkInsightsAnalysisId>nia-1</networkInsightsAnalysisId>
    <networkInsightsAnalysisArn>arn:aws:ec2:us-east-1:1:network-insights-analysis/nia-1</networkInsightsAnalysisArn>
    <networkInsightsPathId>nip-1</networkInsightsPathId>
    <startDate>2026-08-05T12:00:00Z</startDate>
    <status>running</status>
    </networkInsightsAnalysis></StartNetworkInsightsAnalysisResponse>
    """

    parsed = AwsSDK.EC2.parse_start_network_insights_analysis_for_test(xml)

    analysis = parsed.network_insights_analysis
    assert analysis.network_insights_analysis_id == "nia-1"
    assert analysis.status == "running"
    # A running analysis has no verdict yet: nil, not false.
    assert analysis.network_path_found == nil
  end

  test "DescribeNetworkInsightsAnalyses keeps status, path-found flag, and explanations" do
    xml = """
    <DescribeNetworkInsightsAnalysesResponse><networkInsightsAnalysisSet><item>
    <networkInsightsAnalysisId>nia-1</networkInsightsAnalysisId>
    <networkInsightsPathId>nip-1</networkInsightsPathId>
    <startDate>2026-08-05T12:00:00Z</startDate>
    <status>succeeded</status><networkPathFound>false</networkPathFound>
    <explanationSet><item>
    <direction>ingress</direction><explanationCode>ENI_SG_RULES_MISMATCH</explanationCode>
    <networkInterface><id>eni-1</id><arn>arn:aws:ec2:us-east-1:1:network-interface/eni-1</arn></networkInterface>
    <securityGroupSet><item><id>sg-1</id></item></securityGroupSet>
    <port>443</port>
    </item></explanationSet>
    <forwardPathComponentSet><item>
    <sequenceNumber>1</sequenceNumber>
    <component><id>i-1</id><name>web</name></component>
    <subnet><id>subnet-1</id></subnet>
    <outboundHeader><protocol>6</protocol>
    <sourceAddressSet><item>10.0.1.5/32</item></sourceAddressSet>
    <destinationAddressSet><item>10.0.2.9/32</item></destinationAddressSet>
    <destinationPortRangeSet><item><from>443</from><to>443</to></item></destinationPortRangeSet>
    </outboundHeader>
    </item></forwardPathComponentSet>
    </item></networkInsightsAnalysisSet></DescribeNetworkInsightsAnalysesResponse>
    """

    parsed = AwsSDK.EC2.parse_describe_network_insights_analyses_for_test(xml)

    assert [analysis] = parsed.network_insights_analysis_set
    assert analysis.status == "succeeded"
    assert analysis.network_path_found == false
    assert [explanation] = analysis.explanation_set
    assert explanation.explanation_code == "ENI_SG_RULES_MISMATCH"
    assert explanation.network_interface.id == "eni-1"
    assert explanation.security_groups == [%{id: "sg-1", arn: "", name: ""}]
    assert explanation.port == 443
    assert [hop] = analysis.forward_path_component_set
    assert hop.sequence_number == 1
    assert hop.component.id == "i-1"
    assert hop.outbound_header.destination_port_ranges == [%{from: 443, to: 443}]
    assert hop.outbound_header.source_addresses == ["10.0.1.5/32"]
    assert parsed.next_token == ""
  end

  test "DeleteNetworkInsightsPath returns the deleted path id" do
    xml = """
    <DeleteNetworkInsightsPathResponse>
    <networkInsightsPathId>nip-1</networkInsightsPathId>
    </DeleteNetworkInsightsPathResponse>
    """

    parsed = AwsSDK.EC2.parse_delete_network_insights_path_for_test(xml)

    assert parsed.network_insights_path_id == "nip-1"
  end

  test "DescribeScalingActivities keeps status, cause, and details" do
    xml = """
    <DescribeScalingActivitiesResponse><DescribeScalingActivitiesResult>
    <Activities><member>
    <ActivityId>act-1</ActivityId>
    <AutoScalingGroupName>web-asg</AutoScalingGroupName>
    <Description>Terminating EC2 instance: i-1</Description>
    <Cause>instance refresh</Cause>
    <StartTime>2026-08-05T12:00:00Z</StartTime>
    <EndTime>2026-08-05T12:05:00Z</EndTime>
    <StatusCode>Successful</StatusCode>
    <Progress>100</Progress>
    <Details>{"Subnet ID":"subnet-1"}</Details>
    <AutoScalingGroupARN>arn:aws:autoscaling:us-east-1:1:autoScalingGroup:x:autoScalingGroupName/web-asg</AutoScalingGroupARN>
    </member></Activities>
    <NextToken>tok</NextToken>
    </DescribeScalingActivitiesResult></DescribeScalingActivitiesResponse>
    """

    parsed = AwsSDK.AutoScaling.parse_describe_scaling_activities_for_test(xml)

    assert [activity] = parsed.activities
    assert activity.activity_id == "act-1"
    assert activity.auto_scaling_group_name == "web-asg"
    assert activity.status_code == "Successful"
    assert activity.status_message == ""
    assert activity.cause == "instance refresh"
    assert activity.progress == 100
    assert activity.details == ~s({"Subnet ID":"subnet-1"})
    assert parsed.next_token == "tok"
  end

  test "ModifyListener returns the listener with its new default actions" do
    xml = """
    <ModifyListenerResponse><ModifyListenerResult><Listeners><member>
    <ListenerArn>arn:listener/1</ListenerArn>
    <LoadBalancerArn>arn:lb/1</LoadBalancerArn>
    <Port>443</Port><Protocol>HTTPS</Protocol>
    <DefaultActions><member>
    <Type>fixed-response</Type>
    <FixedResponseConfig><StatusCode>503</StatusCode>
    <ContentType>text/plain</ContentType><MessageBody>maintenance</MessageBody>
    </FixedResponseConfig>
    </member></DefaultActions>
    </member></Listeners></ModifyListenerResult></ModifyListenerResponse>
    """

    parsed = AwsSDK.ElasticLoadBalancingV2.parse_modify_listener(xml)

    assert [listener] = parsed.listeners
    assert listener.listener_arn == "arn:listener/1"
    assert listener.port == 443
    assert [action] = listener.default_actions
    assert action.type == "fixed-response"
    assert action.fixed_response_config.status_code == "503"
    assert action.fixed_response_config.message_body == "maintenance"
  end

  test "GetInstanceProfile keeps the profile identity and its roles" do
    xml = """
    <GetInstanceProfileResponse><GetInstanceProfileResult><InstanceProfile>
    <Path>/</Path>
    <InstanceProfileName>web</InstanceProfileName>
    <InstanceProfileId>AIPAEXAMPLE</InstanceProfileId>
    <Arn>arn:aws:iam::123456789012:instance-profile/web</Arn>
    <CreateDate>2026-01-01T00:00:00Z</CreateDate>
    <Roles><member>
    <RoleName>web-role</RoleName><RoleId>AROAEXAMPLE</RoleId>
    <Arn>arn:aws:iam::123456789012:role/web-role</Arn><Path>/</Path>
    <CreateDate>2026-01-01T00:00:00Z</CreateDate>
    </member></Roles>
    <Tags><member><Key>Team</Key><Value>ops</Value></member></Tags>
    </InstanceProfile></GetInstanceProfileResult></GetInstanceProfileResponse>
    """

    parsed = AwsSDK.IAM.parse_instance_profile_for_test(xml)

    profile = parsed.instance_profile
    assert profile.instance_profile_name == "web"
    assert profile.instance_profile_id == "AIPAEXAMPLE"
    assert profile.arn == "arn:aws:iam::123456789012:instance-profile/web"
    assert profile.create_date == "2026-01-01T00:00:00Z"
    assert [role] = profile.roles
    assert role.role_name == "web-role"
    assert profile.tags == [%{key: "Team", value: "ops"}]
  end

  test "DeleteObjects body encodes keys, version ids, and quiet" do
    xml =
      AwsSDK.S3.XMLBuilder.build_delete(
        ["plain.txt", %{key: "reports/2026.csv", version_id: "v1"}],
        true
      )

    assert xml ==
             ~s(<Delete xmlns="http://s3.amazonaws.com/doc/2006-03-01/">) <>
               "<Object><Key>plain.txt</Key></Object>" <>
               "<Object><Key>reports/2026.csv</Key><VersionId>v1</VersionId></Object>" <>
               "<Quiet>true</Quiet>" <>
               "</Delete>"
  end

  test "DeleteObjects result keeps deleted entries and per-key errors" do
    xml = """
    <DeleteResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
    <Deleted><Key>a.txt</Key></Deleted>
    <Deleted><Key>b.txt</Key><VersionId>v2</VersionId>
    <DeleteMarker>true</DeleteMarker><DeleteMarkerVersionId>dm1</DeleteMarkerVersionId></Deleted>
    <Error><Key>c.txt</Key><Code>AccessDenied</Code><Message>Access Denied</Message></Error>
    </DeleteResult>
    """

    parsed = AwsSDK.S3.XMLParser.parse_delete_result(xml)

    assert [a, b] = parsed.deleted
    assert a.key == "a.txt"
    assert b.version_id == "v2"
    assert b.delete_marker == true
    assert b.delete_marker_version_id == "dm1"
    assert [err] = parsed.error
    assert err.key == "c.txt"
    assert err.code == "AccessDenied"
    assert err.message == "Access Denied"
  end
end
