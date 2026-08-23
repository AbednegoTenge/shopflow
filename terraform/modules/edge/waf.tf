

resource "aws_wafv2_web_acl" "main" {
    name = "shopflow-web-acl"
    scope = "CLOUDFRONT"

    default_action {
      allow {}
    }

    rule {
        name = "AWS-AWSManagedRulesCommonRuleSet"
        priority = 1

        override_action {
          none {}
        }

        statement {
          managed_rule_group_statement {
            name = "AWSManagedRulesCommonRuleSet"
            vendor_name = "AWS"
          }
        }

        visibility_config {
          cloudwatch_metrics_enabled = true
          metric_name = "commonRuleSet"
          sampled_requests_enabled = true
        }
    }

    rule {
        name = "AWS-AWSManagedRulesSQLiRuleSet"
        priority = 2

        override_action {
          none {}
        }

        statement {
          managed_rule_group_statement {
            name = "AWSManagedRulesSQLiRuleSet"
            vendor_name = "AWS"
          }
        }

        visibility_config {
          cloudwatch_metrics_enabled = true
          metric_name = "sqliRuleSet"
          sampled_requests_enabled = true
        }
    }

    rule {
      name = "RateLimit"
      priority = 3
      action {
        block {}
      }

      statement {
        rate_based_statement {
            limit = 2000
            aggregate_key_type = "IP"
        }
      }

      visibility_config {
          cloudwatch_metrics_enabled = true
          metric_name = "rateLimit"
          sampled_requests_enabled = true
        }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name = "shopflow-waf"
      sampled_requests_enabled = true
    }
}