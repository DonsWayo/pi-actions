variable "github_owner" {
  description = "GitHub organization or username that owns the repo (used as the runner registration target)."
  type        = string
}

variable "repo_name" {
  description = "Name of the GitHub repository the self-hosted runner is registered to."
  type        = string
}

variable "create_repo" {
  description = "Create the repository if it does not exist. Set to false if it already exists."
  type        = bool
  default     = true
}

variable "repo_visibility" {
  description = "Visibility of the repository (owner must exist)."
  type        = string
  default     = "public"
  validation {
    condition     = contains(["public", "private", "internal"], var.repo_visibility)
    error_message = "repo_visibility must be one of public, private, internal."
  }
}

variable "runner_name" {
  description = "Unique name of the runner (also used as the compute hostname)."
  type        = string
  default     = "pi-runner-01"
}

variable "runner_labels" {
  description = "Runner labels used for runs-on matching. self-hosted/linux/arm64 are always appended."
  type        = list(string)
  default     = ["pi", "arm64", "linux", "self-hosted"]
  nullable    = false
}

variable "runner_scope" {
  description = "Where the runner is registered: 'repo' (default) or 'org' (for shared runner groups)."
  type        = string
  default     = "repo"
  validation {
    condition     = contains(["repo", "org"], var.runner_scope)
    error_message = "runner_scope must be 'repo' or 'org'."
  }
}

variable "runner_group" {
  description = "Organization runner group name to place the runner into (only used when runner_scope = 'org')."
  type        = string
  default     = "default"
}

variable "runner_user" {
  description = "Non-root system user the runner runs as on the Pi."
  type        = string
  default     = "runner"
}

variable "runner_version" {
  description = "GitHub Actions runner version to install (arm64). Leave empty to use the latest."
  type        = string
  default     = ""
}

variable "wifi_ssid" {
  description = "Pi Wi-Fi SSID the SD card is flashed for. Overrides the fallback in flash.sh."
  type        = string
  default     = ""
}

variable "wifi_password" {
  description = "Pi Wi-Fi password. Marked sensitive."
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_ssh" {
  description = "Enable SSH on first boot (useful for debugging; the runner needs no SSH)."
  type        = bool
  default     = false
}

variable "timezone" {
  description = "Timezone configured on the Pi."
  type        = string
  default     = "UTC"
}

variable "runtime_in_minutes" {
  description = "How long (minutes) before the Pi self-registers. Used to size the registration-token bootstrap window."
  type        = number
  default     = 10
}
