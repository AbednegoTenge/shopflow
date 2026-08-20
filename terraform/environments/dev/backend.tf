terraform {
  backend "s3" {
    bucket = "shopflow-tfstate-abed"
    key = "dev/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "shopflow-tf-lock"
    encrypt = true
  }
}