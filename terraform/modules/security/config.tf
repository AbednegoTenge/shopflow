data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "config" {
    bucket        = "shopflow-config-${data.aws_caller_identity.current.account_id}"
    force_destroy = true
    tags          = { Name = "ShopFlow-config" }
}

resource "aws_s3_bucket_public_access_block" "config" {
    bucket                  = aws_s3_bucket.config.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
    bucket = aws_s3_bucket.config.id
    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm = "AES256"
        }
    }
}

data "aws_iam_policy_document" "config_bucket_policy" {
    statement {
        sid    = "AWSConfigBucketPermissionsCheck"
        effect = "Allow"
        principals {
            type        = "Service"
            identifiers = ["config.amazonaws.com"]
        }
        actions   = ["s3:GetBucketAcl"]
        resources = [aws_s3_bucket.config.arn]
    }

    statement {
        sid    = "AWSConfigBucketDelivery"
        effect = "Allow"
        principals {
            type        = "Service"
            identifiers = ["config.amazonaws.com"]
        }
        actions   = ["s3:PutObject"]
        resources = ["${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]
        condition {
            test     = "StringEquals"
            variable = "aws:SourceAccount"
            values   = [data.aws_caller_identity.current.account_id]
        }
    }
}

resource "aws_s3_bucket_policy" "config" {
    bucket = aws_s3_bucket.config.id
    policy = data.aws_iam_policy_document.config_bucket_policy.json
}

resource "aws_iam_role" "config" {
    name = "shopflow-config-role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect    = "Allow"
            Principal = { Service = "config.amazonaws.com" }
            Action    = "sts:AssumeRole"
        }]
    })
}

resource "aws_iam_role_policy_attachment" "config" {
    role       = aws_iam_role.config.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "main" {
    name     = "shopflow-recorder"
    role_arn = aws_iam_role.config.arn

    recording_group {
        all_supported                 = true
        include_global_resource_types = true
    }
}

resource "aws_config_delivery_channel" "main" {
    name           = "shopflow-delivery-channel"
    s3_bucket_name = aws_s3_bucket.config.id
    depends_on     = [aws_s3_bucket_policy.config]
}

resource "aws_config_configuration_recorder_status" "main" {
    name       = aws_config_configuration_recorder.main.name
    is_enabled = true
    depends_on = [aws_config_delivery_channel.main]
}
