locals {
  ecr_repositories = {
    frontend              = "${var.project_name}/frontend"
    productcatalogservice = "${var.project_name}/productcatalogservice"
    currencyservice       = "${var.project_name}/currencyservice"
  }

  # ECR repos are shared across environments; staging creates them, production reads them.
  create_ecr = terraform.workspace == "staging"

  ecr_urls = {
    for key, name in local.ecr_repositories :
    key => local.create_ecr ? aws_ecr_repository.app[key].repository_url : data.aws_ecr_repository.app[key].repository_url
  }
}

resource "aws_ecr_repository" "app" {
  for_each             = local.create_ecr ? local.ecr_repositories : {}
  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

data "aws_ecr_repository" "app" {
  for_each = local.create_ecr ? {} : local.ecr_repositories
  name     = each.value
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = local.create_ecr ? local.ecr_repositories : {}
  repository = aws_ecr_repository.app[each.key].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}