import {
  ArnFormat, CfnOutput, CfnParameter, Duration, Fn, IgnoreMode, RemovalPolicy, Stack, StackProps,
} from "aws-cdk-lib";
import * as cloudfront from "aws-cdk-lib/aws-cloudfront";
import * as origins from "aws-cdk-lib/aws-cloudfront-origins";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as elbv2 from "aws-cdk-lib/aws-elasticloadbalancingv2";
import { InstanceTarget } from "aws-cdk-lib/aws-elasticloadbalancingv2-targets";
import * as iam from "aws-cdk-lib/aws-iam";
import * as logs from "aws-cdk-lib/aws-logs";
import * as opensearch from "aws-cdk-lib/aws-opensearchservice";
import * as rds from "aws-cdk-lib/aws-rds";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as assets from "aws-cdk-lib/aws-s3-assets";
import * as waf from "aws-cdk-lib/aws-wafv2";
import { Construct } from "constructs";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const modelId = "amazon.nova-pro-v1:0";
const secretParameter = "/greatschools/guided-search/secret-key-base";
const domainName = "greatschools-guided";

export class GreatSchoolsStack extends Stack {
  constructor(scope: Construct, id: string, props: StackProps) {
    super(scope, id, props);

    const originZones = new CfnParameter(this, "OriginAvailabilityZones", {
      type: "CommaDelimitedList",
      description: "Two us-east-1 availability zone names that support CloudFront VPC origins",
      allowedPattern: "us-east-1[a-z]",
    });
    const clientCidrs = new CfnParameter(this, "AllowedClientCidrs", {
      type: "CommaDelimitedList",
      description: "IPv4 CIDRs for the demo audience, such as each viewer's public IPv4 followed by /32",
      allowedPattern: "([0-9]{1,3}\\.){3}[0-9]{1,3}/([1-9]|[12][0-9]|3[0-2])",
    });
    const agentClass = adapterContext(this, "agentClass", "GuidedSearch::DemoAgent");
    const retrieverClass = adapterContext(this, "retrieverClass", "GuidedSearch::DemoSearch");

    const vpc = new ec2.Vpc(this, "Vpc", {
      // In us-east-1 CloudFront VPC origins are unavailable in use1-az3.
      // Zone names for a zone ID can vary across accounts.
      availabilityZones: [Fn.select(0, originZones.valueAsList), Fn.select(1, originZones.valueAsList)],
      natGateways: 0,
      subnetConfiguration: [
        { name: "Public", subnetType: ec2.SubnetType.PUBLIC, cidrMask: 24 },
        { name: "Data", subnetType: ec2.SubnetType.PRIVATE_ISOLATED, cidrMask: 24 },
      ],
    });
    const dataSubnets = { subnetType: ec2.SubnetType.PRIVATE_ISOLATED };
    const appSecurity = new ec2.SecurityGroup(this, "AppSecurity", { vpc });
    const albSecurity = new ec2.SecurityGroup(this, "AlbSecurity", { vpc });
    // AWS-managed com.amazonaws.global.cloudfront.origin-facing prefix list in us-east-1.
    albSecurity.addIngressRule(ec2.Peer.prefixList("pl-3b927c52"), ec2.Port.tcp(80));
    appSecurity.addIngressRule(albSecurity, ec2.Port.tcp(80));

    const role = new iam.Role(this, "AppRole", { assumedBy: new iam.ServicePrincipal("ec2.amazonaws.com") });
    role.addToPolicy(new iam.PolicyStatement({
      actions: [
        "ssm:UpdateInstanceInformation", "ssmmessages:CreateControlChannel", "ssmmessages:OpenControlChannel",
        "ssmmessages:CreateDataChannel", "ssmmessages:OpenDataChannel",
      ],
      resources: ["*"],
    }));
    role.addToPolicy(new iam.PolicyStatement({
      actions: ["ssm:GetParameter"],
      resources: [this.formatArn({ service: "ssm", resource: "parameter", resourceName: secretParameter.slice(1) })],
    }));
    role.addToPolicy(new iam.PolicyStatement({
      actions: ["bedrock:InvokeModel"],
      resources: [this.formatArn({
        service: "bedrock", account: "", resource: "foundation-model", resourceName: modelId,
        arnFormat: ArnFormat.SLASH_RESOURCE_NAME,
      })],
    }));

    const database = new rds.DatabaseInstance(this, "Database", {
      vpc,
      vpcSubnets: dataSubnets,
      publiclyAccessible: false,
      engine: rds.DatabaseInstanceEngine.mysql({ version: rds.MysqlEngineVersion.VER_8_4_8 }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T4G, ec2.InstanceSize.MICRO),
      credentials: rds.Credentials.fromGeneratedSecret("greatschools_admin"),
      databaseName: "greatschools_production",
      parameters: { require_secure_transport: "ON" },
      allocatedStorage: 20,
      storageEncrypted: true,
      multiAz: false,
      backupRetention: Duration.days(1),
      removalPolicy: RemovalPolicy.DESTROY,
      deleteAutomatedBackups: true,
    });
    database.connections.allowDefaultPortFrom(appSecurity);
    database.secret!.grantRead(role);

    const searchSecurity = new ec2.SecurityGroup(this, "SearchSecurity", { vpc });
    searchSecurity.addIngressRule(appSecurity, ec2.Port.tcp(443));
    const domainArn = this.formatArn({ service: "es", resource: "domain", resourceName: domainName });
    const indexPaths = ["schools*", "programs*", "reviews*"].map(prefix => `${domainArn}/${prefix}`);
    const domain = new opensearch.Domain(this, "Search", {
      domainName,
      version: opensearch.EngineVersion.OPENSEARCH_2_19,
      vpc,
      vpcSubnets: [{ ...dataSubnets, onePerAz: true, availabilityZones: [vpc.availabilityZones[0]] }],
      securityGroups: [searchSecurity],
      capacity: { dataNodes: 1, dataNodeInstanceType: "t3.small.search" },
      ebs: { volumeSize: 20, volumeType: ec2.EbsDeviceVolumeType.GP3 },
      enforceHttps: true,
      tlsSecurityPolicy: opensearch.TLSSecurityPolicy.TLS_1_2,
      nodeToNodeEncryption: true,
      encryptionAtRest: { enabled: true },
      removalPolicy: RemovalPolicy.DESTROY,
      accessPolicies: [
        new iam.PolicyStatement({
          principals: [role], actions: ["es:ESHttpGet", "es:ESHttpHead"], resources: [`${domainArn}/*`],
        }),
        new iam.PolicyStatement({
          principals: [role], actions: ["es:ESHttpPost", "es:ESHttpPut", "es:ESHttpDelete"], resources: indexPaths,
        }),
      ],
    });

    const dataBucket = new s3.Bucket(this, "SyntheticData", {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY,
    });
    dataBucket.grantRead(role, "datasets/*");

    const logGroup = new logs.LogGroup(this, "AppLogs", {
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY,
    });
    logGroup.grantWrite(role);
    role.addToPolicy(new iam.PolicyStatement({
      actions: ["logs:DescribeLogStreams"],
      resources: [logGroup.logGroupArn],
    }));

    const release = new assets.Asset(this, "RailsRelease", {
      path: resolve(__dirname, "../.."),
      ignoreMode: IgnoreMode.GLOB,
      exclude: [
        "infra", ".git", ".agents", ".aws", ".codex", ".bundle", ".env*", "vendor/bundle",
        "log", "tmp", "storage", "node_modules", "public/assets", "app/assets/builds/*.css",
        "app/assets/builds/tailwind", "test",
        "config/master.key", "config/credentials", "**/*.pem", "**/.DS_Store",
      ],
    });
    release.grantRead(role);

    const deploy = join(__dirname, "../deploy");
    const userData = ec2.UserData.forLinux();
    userData.addCommands("set -euo pipefail",
      `export AWS_REGION='${this.region}' AWS_DEFAULT_REGION='${this.region}'`,
      `export RELEASE_URI='${release.s3ObjectUrl}'`,
      `export LOG_GROUP='${logGroup.logGroupName}'`,
      "install -d -m 0755 /etc/greatschools",
      "cat > /etc/greatschools/config <<'CONFIG'",
      `AWS_REGION='${this.region}'
AWS_DEFAULT_REGION='${this.region}'
DB_HOST='${database.dbInstanceEndpointAddress}'
DB_SECRET_ID='${database.secret!.secretArn}'
SECRET_KEY_BASE_PARAMETER='${secretParameter}'
OPENSEARCH_URL='https://${domain.domainEndpoint}'
BEDROCK_MODEL_ID='${modelId}'
SYNTHETIC_DATA_BUCKET='${dataBucket.bucketName}'
GUIDED_SEARCH_AGENT='${agentClass}'
GUIDED_SEARCH_RETRIEVER='${retrieverClass}'`,
      "CONFIG",
      ...["greatschools.service", "nginx.conf", "with-config"].flatMap(filename => [
        `cat > /etc/greatschools/${filename} <<'FILE'`,
        readFileSync(join(deploy, filename), "utf8").trimEnd(),
        "FILE",
      ]),
      readFileSync(join(deploy, "bootstrap.sh"), "utf8").trimEnd(),
    );
    const instance = new ec2.Instance(this, "RailsHost", {
      vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
      associatePublicIpAddress: true,
      securityGroup: appSecurity,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.SMALL),
      machineImage: ec2.MachineImage.latestAmazonLinux2023(),
      requireImdsv2: true,
      role,
      userData,
      userDataCausesReplacement: true,
      blockDevices: [{
        deviceName: "/dev/xvda",
        volume: ec2.BlockDeviceVolume.ebs(16, { encrypted: true, deleteOnTermination: true }),
      }],
    });

    const loadBalancer = new elbv2.ApplicationLoadBalancer(this, "LoadBalancer", {
      vpc, vpcSubnets: dataSubnets, internetFacing: false, securityGroup: albSecurity,
      idleTimeout: Duration.seconds(90),
    });
    const listener = loadBalancer.addListener("Http", {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      open: false,
    });
    const targets = listener.addTargets("Rails", {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      healthCheck: { path: "/up", healthyHttpCodes: "200" },
    });
    targets.addTarget(new InstanceTarget(instance, 80));

    const origin = new cloudfront.VpcOrigin(this, "RailsOrigin", {
      endpoint: cloudfront.VpcOriginEndpoint.applicationLoadBalancer(loadBalancer),
      protocolPolicy: cloudfront.OriginProtocolPolicy.HTTP_ONLY,
    });
    origin.node.addDependency(listener, vpc.internetConnectivityEstablished);

    const viewerIps = new waf.CfnIPSet(this, "DemoViewerIps", {
      scope: "CLOUDFRONT", ipAddressVersion: "IPV4", addresses: clientCidrs.valueAsList,
    });
    const access = new waf.CfnWebACL(this, "DemoAccess", {
      scope: "CLOUDFRONT",
      defaultAction: { block: {} },
      visibilityConfig: { cloudWatchMetricsEnabled: true, metricName: "GreatSchoolsDemo", sampledRequestsEnabled: false },
      rules: [{
        name: "AllowDemoViewers",
        priority: 0,
        action: { allow: {} },
        statement: { ipSetReferenceStatement: { arn: viewerIps.attrArn } },
        visibilityConfig: { cloudWatchMetricsEnabled: true, metricName: "DemoViewers", sampledRequestsEnabled: false },
      }],
    });
    const distribution = new cloudfront.Distribution(this, "DemoSite", {
      enableIpv6: false,
      webAclId: access.attrArn,
      defaultBehavior: {
        origin: origins.VpcOrigin.withVpcOrigin(origin, { readTimeout: Duration.seconds(75) }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
        originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER,
      },
    });

    new CfnOutput(this, "Url", { value: `https://${distribution.distributionDomainName}` });
    new CfnOutput(this, "InstanceId", { value: instance.instanceId });
    new CfnOutput(this, "AppLogGroup", { value: logGroup.logGroupName });
    new CfnOutput(this, "SyntheticDataBucket", { value: dataBucket.bucketName });
  }
}

function adapterContext(stack: Stack, key: string, defaultClass: string): string {
  const value = stack.node.tryGetContext(key) ?? defaultClass;
  if (typeof value !== "string" || !/^[A-Z][A-Za-z0-9_]*(::[A-Z][A-Za-z0-9_]*)*$/.test(value)) {
    throw new Error(`${key} must be a Ruby class name`);
  }
  return value;
}
