resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)
  #checkov:skip=CKV_AWS_136:AES256 (AWS-managed) encryption is sufficient for lab images; KMS CMK adds cost with no extra control we use.

  name = "${var.name}/${each.value}"
  # Immutable tags: an image tag (git SHA) always means the same bytes, which is
  # what makes "roll back to <sha>" trustworthy.
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_last_images
      }
      action = { type = "expire" }
    }]
  })
}
