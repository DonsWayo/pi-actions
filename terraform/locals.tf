data "github_repository" "this" {
  count = var.create_repo ? 0 : 1
  name  = var.repo_name
}

locals {
  repo_id   = var.create_repo ? github_repository.this[0].repo_id : data.github_repository.this[0].repo_id
  repo_full = var.create_repo ? github_repository.this[0].full_name : data.github_repository.this[0].full_name
  repo_url  = var.create_repo ? github_repository.this[0].html_url : data.github_repository.this[0].html_url
}
