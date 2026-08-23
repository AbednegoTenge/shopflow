data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "static_assets_policy" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static_assets.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
    }
  }
}


resource "aws_s3_bucket" "static_assets" {
    bucket = "shopflow-static-assets-${data.aws_caller_identity.current.account_id}"
    force_destroy = true
    tags = {
      Name = "ShopFlow-static-assets"
    }
}

resource "aws_s3_bucket_policy" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id
  policy = data.aws_iam_policy_document.static_assets_policy.json
}

resource "aws_s3_bucket_versioning" "static_assets" {
    bucket = aws_s3_bucket.static_assets.id
    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_s3_bucket_public_access_block" "static_assets" {
    bucket = aws_s3_bucket.static_assets.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static_assets" {
    bucket = aws_s3_bucket.static_assets.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket" "backups" {
    bucket = "shopflow-backups-${data.aws_caller_identity.current.account_id}"
    force_destroy = true
    tags = {
      Name = "ShopFlow-backups"
    }
}

resource "aws_s3_bucket_versioning" "backups" {
    bucket = aws_s3_bucket.backups.id
    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
    bucket = aws_s3_bucket.backups.id

    rule {
        id = "transition-old-backups"
        status = "Enabled"
        transition {
            days = 30
            storage_class = "GLACIER"
        }
    }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
    bucket = aws_s3_bucket.backups.id
    rule {
        apply_server_side_encryption_by_default {
          kms_master_key_id = var.kms_key_arn
          sse_algorithm = "aws:kms"
        }
    } 
}

resource "aws_s3_bucket_public_access_block" "backups" {
    bucket = aws_s3_bucket.backups.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "static_assets" {
    name = "shopflow-static-oac"
    origin_access_control_origin_type = "s3"
    signing_behavior = "always"
    signing_protocol = "sigv4"
}
