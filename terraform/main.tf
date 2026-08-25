resource "github_repository" "this" {
  count = var.create_repo ? 1 : 0

  name        = var.repo_name
  description = "Self-hosted GitHub Actions runner fleet powered by a Raspberry Pi."
  visibility  = var.repo_visibility

  archived     = false
  auto_init    = true
  has_issues   = true
  has_projects = false
  has_wiki     = false

  # Public repos of self-hosted runners: protect the default branch and require
  # reviewing a PR that injects workflow changes. See README security section.
}

resource "github_branch_default" "this" {
  count      = var.create_repo ? 1 : 0
  repository = github_repository.this[0].name
  branch     = "main"
}

# Organization-level runner group (only relevant when the runner is org-scoped
# and you want it isolated from other repos). Creates or reuses the group.
resource "github_actions_runner_group" "this" {
  count = var.runner_scope == "org" ? 1 : 0

  name = var.runner_group

  visibility                 = "selected"
  selected_repository_ids    = [local.repo_id]
  allows_public_repositories = true
}
