# Short-lived (1h) registration token burned by config.sh on the Pi so it can
# self-register with zero SSH. This is the secret the cloud-init bootstrap uses.
# The data source is selected by resolver scope.
#
# repo: github_actions_registration_token  (repository = repo name)
# org : github_actions_organization_registration_token (organisation-level)

data "github_actions_registration_token" "this" {
  count      = var.runner_scope == "repo" ? 1 : 0
  repository = var.repo_name
  depends_on = [terraform_data.repo_ready]
}

# Marker node that guarantees the repo exists before the token is read. The
# token endpoint 404s against a repo that has not been created yet.
resource "terraform_data" "repo_ready" {
  input = local.repo_id
}

data "github_actions_organization_registration_token" "this" {
  count = var.runner_scope == "org" ? 1 : 0
}

locals {
  registration_token = try(
    data.github_actions_registration_token.this[0].token,
    data.github_actions_organization_registration_token.this[0].token,
    null,
  )

  # Absolute label list the runner must present so workflow runs-on matches.
  labels = toset(concat(["self-hosted", "linux", "arm64"], var.runner_labels))
}
