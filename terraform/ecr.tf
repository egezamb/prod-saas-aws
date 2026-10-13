resource "aws_ecr_repository" "app" {
  name = local.name
  # A tag names one image forever, so a deployed version can always be traced to its commit and
  # nothing can be pushed over it. Deploys push the commit SHA; :latest is pushed once, by hand,
  # for the first apply (see docs/DECISIONS.md).
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = local.name }
}

# Keep only the last 10 images to bound storage cost.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

locals {
  # Use the caller-provided image if set, otherwise the ECR repo's :latest.
  # First apply (no image pushed yet) uses a public placeholder so the plan is
  # valid; push your image and re-apply to run the real app.
  app_image = var.container_image != "" ? var.container_image : "${aws_ecr_repository.app.repository_url}:latest"
}
