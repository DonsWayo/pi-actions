provider "github" {
  # Token is read from GITHUB_TOKEN env var.
  # For org/enterprise scope you can point this at your GHES endpoint:
  #   base_url = "https://ghe.example.com/api/v3/"
  owner = var.github_owner
}
