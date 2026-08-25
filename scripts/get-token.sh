#!/usr/bin/env bash
#
# get-token.sh — fetch a short-lived GitHub Actions runner registration token.
# The token is valid ~1 hour, so call this right before flashing/provisioning.
#
# This is the `gh`-only alternative to `terraform output -raw registration_token`.
#
# Usage:
#   scripts/get-token.sh --owner acme --repo pi-actions            # repo scope
#   scripts/get-token.sh --owner acme       --scope org            # org scope

set -euo pipefail

OWNER=""
REPO=""
SCOPE="repo"

usage() {
  cat <<EOF
Usage: $0 --owner <owner> [--repo <repo>] [--scope repo|org]
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2;;
    --repo)  REPO="$2"; shift 2;;
    --scope) SCOPE="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "unknown: $1" >&2; exit 1;;
  esac
done

command -v gh >/dev/null || { echo "gh CLI is required (brew install gh)" >&2; exit 1; }
[[ -n "$OWNER" ]] || { echo "--owner is required" >&2; exit 1; }
[[ "$SCOPE" == "repo" && -n "$REPO" ]] || [[ "$SCOPE" == "org" ]] || { echo "repo scope requires --repo" >&2; exit 1; }

gh auth status >/dev/null || { echo "run: gh auth login" >&2; exit 1; }

if [[ "$SCOPE" == "org" ]]; then
  gh api -X POST "orgs/${OWNER}/actions/runner-registration-token" --jq .token
else
  gh api -X POST "repos/${OWNER}/${REPO}/actions/runners/registration-token" --jq .token
fi
