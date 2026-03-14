terraform {
  backend "s3" {
    bucket         = "google-aws-demo-tf-state"
    key            = "eks/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
