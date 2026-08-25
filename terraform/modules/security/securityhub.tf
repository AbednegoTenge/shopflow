resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "foundational" {
    standards_arn = "arn:aws:securityhub:us-east-1::standards/aws-foundational-security-best-practices/v/1.0.0"
    depends_on    = [aws_securityhub_account.main]
}
