# Terraform Resource Architecture

This diagram shows the main AWS resources created by the `terraform/environments/dev` root module and the traffic, event, deployment, observability, and security relationships between them.

```mermaid
flowchart LR
    User((Clients))
    GitHub["GitHub Actions"]

    subgraph Edge["module.edge"]
        WAF["aws_wafv2_web_acl.main"]
        CF["aws_cloudfront_distribution.main"]
        OAC["aws_cloudfront_origin_access_control.static_assets"]
        Assets[("aws_s3_bucket.static_assets")]
        Backups[("aws_s3_bucket.backups")]
    end

    subgraph VPC["module.networking: aws_vpc.main · us-east-1a / us-east-1b"]
        IGW["aws_internet_gateway.igw"]
        Public["aws_subnet.publicsubnet1 / publicsubnet2<br/>public route table"]
        NAT["aws_nat_gateway.nat-gw<br/>aws_eip.nat-eip"]
        Private["aws_subnet.privatesubnet1 / privatesubnet2<br/>private route table"]
        SG["Security groups<br/>alb-sg → ecs-sg → rds_sg / cache-sg"]
        KMS["aws_kms_key.main<br/>aws_kms_alias.main"]
        RDSGroup["aws_db_subnet_group.rds-group"]
        CacheGroup["aws_elasticache_subnet_group.elasticache"]
    end

    subgraph Compute["module.compute"]
        ALB["aws_lb.app<br/>aws_lb_listener.http<br/>aws_lb_target_group.app"]
        ECS["aws_ecs_cluster.main<br/>aws_ecs_service.app<br/>aws_ecs_task_definition.app<br/>Fargate ARM64"]
        ECR["aws_ecr_repository.app"]
        AutoScale["aws_appautoscaling_target.ecs<br/>aws_appautoscaling_policy.cpu"]
        AppLogs[("aws_cloudwatch_log_group.app")]
        ComputeIAM["ECS execution/task IAM roles<br/>Secrets Manager · EventBridge · X-Ray · ECS Exec"]
    end

    subgraph Data["module.data"]
        RDS[("aws_db_instance.shopflow<br/>Postgres Multi-AZ")]
        Redis[("aws_elasticache_replication_group.cache<br/>Redis auto-failover")]
    end

    subgraph Async["module.async"]
        EventRule["aws_cloudwatch_event_rule.order_created"]
        EventTarget["aws_cloudwatch_event_target.to_sqs"]
        Queue[("aws_sqs_queue.orders_queue")]
        DLQ[("aws_sqs_queue.orders_dlq")]
        Worker["aws_lambda_function.worker<br/>VPC, ARM64"]
        Trigger["aws_lambda_event_source_mapping.sqs_trigger"]
        LambdaIAM["Lambda IAM role/policies"]
    end

    subgraph Ops["module.observability"]
        Dashboard["aws_cloudwatch_dashboard.main"]
        Alarms["CloudWatch metric alarms"]
        SNS["aws_sns_topic.alerts<br/>email subscription"]
    end

    subgraph Security["module.security"]
        GuardDuty["aws_guardduty_detector.main"]
        SecHub["aws_securityhub_account.main<br/>Foundational standard"]
        Config["AWS Config recorder + delivery channel"]
        ConfigBucket[("aws_s3_bucket.config")]
        Analyzer["aws_accessanalyzer_analyzer.main"]
        FlowLogs["aws_flow_log.vpc<br/>CloudWatch log group"]
        SecurityIAM["Config / Flow Logs IAM roles"]
    end

    subgraph CICD["module.cicd"]
        OIDC["aws_iam_openid_connect_provider.github"]
        DeployRole["aws_iam_role.github_deploy<br/>scoped OIDC trust + deploy policy"]
    end

    User --> WAF --> CF
    CF -->|dynamic API origin| ALB
    CF -->|static assets origin| Assets
    OAC -.-> Assets
    WAF -.-> CF

    ALB --> ECS
    Public --> ALB
    ECS -->|5432| RDS
    ECS -->|6379| Redis
    ECS -->|OrderCreated| EventRule --> EventTarget --> Queue
    Queue --> Trigger --> Worker
    Queue -.->|after 3 failed receives| DLQ
    Worker -->|5432| RDS

    IGW --> Public
    Public --> NAT --> Private
    Private --> ECS
    Private --> RDS
    Private --> Redis
    SG -.-> ALB
    SG -.-> ECS
    SG -.-> RDS
    SG -.-> Redis
    RDSGroup -.-> RDS
    CacheGroup -.-> Redis
    KMS -.-> RDS
    KMS -.-> Assets
    KMS -.-> Backups

    GitHub --> OIDC --> DeployRole
    DeployRole -->|push image| ECR
    DeployRole -->|register revision / update service| ECS
    DeployRole -->|smoke test| ALB
    ComputeIAM -.-> ECS
    LambdaIAM -.-> Worker

    ECS -.-> AppLogs
    ALB -.-> Dashboard
    ECS -.-> Dashboard
    RDS -.-> Dashboard
    Queue -.-> Dashboard
    Dashboard -.-> Alarms --> SNS
    Alarms -.-> ECS
    Alarms -.-> RDS
    Alarms -.-> DLQ

    GuardDuty -.-> VPC
    SecHub -.-> VPC
    Analyzer -.-> CICD
    Config --> ConfigBucket
    SecurityIAM -.-> Config
    FlowLogs --> SecurityIAM
    FlowLogs -.-> VPC
```

## Terraform Module Boundaries

| Module | Primary resources |
| --- | --- |
| `networking` | VPC, public/private subnets, routes, NAT gateway, security groups, subnet groups, KMS key |
| `data` | Multi-AZ RDS PostgreSQL and ElastiCache Redis |
| `compute` | ECR, ALB, ECS Fargate service/task definition, autoscaling, logs, IAM |
| `async` | EventBridge, SQS queue/DLQ, Lambda worker, event source mapping, IAM |
| `edge` | CloudFront, WAF, static-assets and backup S3 buckets, OAC, KMS policy |
| `cicd` | GitHub OIDC provider and scoped deployment role |
| `observability` | CloudWatch dashboard, alarms, SNS topic and email subscription |
| `security` | GuardDuty, Security Hub, AWS Config, Access Analyzer, VPC Flow Logs |
