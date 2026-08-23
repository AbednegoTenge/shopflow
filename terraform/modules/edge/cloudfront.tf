
resource "aws_cloudfront_distribution" "main" {
    enabled = true
    comment = "ShopFlow distribution"

    origin {
      domain_name = aws_s3_bucket.static_assets.bucket_regional_domain_name
      origin_id = "s3-static-assets"
      origin_access_control_id = aws_cloudfront_origin_access_control.static_assets.id
    }

    origin {
        domain_name = var.alb_dns_name
        origin_id = "alb-app"
        custom_origin_config {
          http_port = 80
          https_port = 443
          origin_protocol_policy = "http-only"
          origin_ssl_protocols = ["TLSv1.2"]
        }
    }

    default_cache_behavior {
      target_origin_id = "alb-app"
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods = ["GET", "HEAD"]

      forwarded_values {
        query_string = true
        headers = ["*"]
        cookies { forward = "all" }
      }

      min_ttl = 0
      default_ttl = 0
      max_ttl = 0
    }

    ordered_cache_behavior {
      path_pattern = "assets/*"
      target_origin_id = "s3-static-assets"
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods = ["GET", "HEAD"]
      cached_methods = ["GET", "HEAD"]

      forwarded_values {
        query_string = false
        cookies { forward = "none" }
      }

      min_ttl = 0
      default_ttl = 86400
      max_ttl = 31536000
    }

    restrictions { 
        geo_restriction {
            restriction_type = "none"
        }
    }

    viewer_certificate {
        cloudfront_default_certificate = true
    }
    
    web_acl_id = aws_wafv2_web_acl.main.arn
}