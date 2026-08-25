locals {
  label_string = join(",", local.labels)
  # Extra-vars passed to ansible-pull. The registration token stays OFF the
  # command line: it is written to /etc/pi-actions/registration-token and read
  # by the github-runner role at register time.
  ansible_vars = "runner_scope=${var.runner_scope} runner_name=${var.runner_name} runner_user=${var.runner_user} runner_group=${var.runner_group} runner_labels=${local.label_string} repo_name=${var.repo_name} github_owner=${var.github_owner}"
}

resource "local_file" "user_data" {
  filename = "${path.module}/generated/user-data"
  content = templatefile("${path.module}/templates/user-data.tpl", {
    runner_name        = var.runner_name
    timezone           = var.timezone
    enable_ssh         = var.enable_ssh
    repo_url           = "https://github.com/${var.github_owner}/${var.repo_name}.git"
    git_branch         = "main"
    ansible_vars       = local.ansible_vars
    registration_token = local.registration_token
    repo_name          = var.repo_name
    github_owner       = var.github_owner
  })
}

output "cloud_init_user_data" {
  description = "Rendered cloud-init user-data. Feed to scripts/flash.sh (or cat to the SD boot partition)."
  value       = local_file.user_data.content
  sensitive   = true
}

output "registration_token" {
  description = "Short-lived runner registration token (valid ~1h). Write to the SD card or pass to flash.sh."
  value       = local.registration_token
  sensitive   = true
}

output "runner_labels" {
  value = local.label_string
}

output "repository_url" {
  value = local.repo_url
}
