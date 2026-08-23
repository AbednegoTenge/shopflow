output "cloudfront_domain_name" { value = aws_cloudfront_distribution.main.domain_name }
output "static_assets_bucket"   { value = aws_s3_bucket.static_assets.bucket }
output "backups_bucket"         { value = aws_s3_bucket.backups.bucket }