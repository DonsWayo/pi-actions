#!/usr/bin/env bash
#
# register.sh — (re)register a runner on an already-reachable Pi over SSH.
# This is the "I want to fix / reconfigure an existing Pi" path, not the
# zero-SSH first-boot path (that's flash.sh + cloud-init + ansible-pull).
#
# It refreshes a registration token and runs the provision playbook via Ansible.
#
# Usage:
#   scripts/register.sh --owner acme --repo pi-actions --host 192.168.1.50 \
#     --runner-name pi-runner-01 --user runner

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OWNER=""
REPO=""
HOST=""
RUNNER_USER="runner"
RUNNER_NAME="pi-runner-01"
SCOPE="repo"
GROUP="default"
LABELS="self-hosted,linux,arm64,pi"

usage() {
  cat <<EOF
Usage: $0 --owner <owner> --repo <repo> --host <ip|name> [options]
  --runner-name <name>   (default pi-runner-01)
  --user <user>          SSH user (default runner)
  --scope <repo|org>     (default repo)
  --group <name>         org runner group when --scope org
  --labels <list>        (default self-hosted,linux,arm64,pi)
  --inventory <file>     custom Ansible inventory (default ansible/inventory.yml)
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)       OWNER="$2"; shift 2;;
    --repo)        REPO="$2"; shift 2;;
    --host)        HOST="$2"; shift 2;;
    --runner-name) RUNNER_NAME="$2"; shift 2;;
    --user)        RUNNER_USER="$2"; shift 2;;
    --scope)       SCOPE="$2"; shift 2;;
    --group)       GROUP="$2"; shift 2;;
    --labels)      LABELS="$2"; shift 2;;
    --inventory)   INVENTORY="$2"; shift 2;;
    -h|--help)     usage;;
    *) echo "unknown: $1" >&2; exit 1;;
  esac
done

[[ -n "$OWNER" && -n "$REPO" && -n "$HOST" ]] || { echo "--owner, --repo and --host are required" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh CLI is required" >&2; exit 1; }

TOKEN="$("$SCRIPT_DIR/get-token.sh" --owner "$OWNER" --repo "$REPO" --scope "$SCOPE")"

INVENTORY="${INVENTORY:-$SCRIPT_DIR/../ansible/inventory.yml}"
# Generate a temp inventory pointing at the target host.
TMP_INV="$(mktemp)"
cat > "$TMP_INV" <<EOF
all:
  children:
    runners:
      hosts:
        pi-runner-01:
          ansible_host: ${HOST}
          ansible_user: ${RUNNER_USER}
EOF

echo "Registering runner ${RUNNER_NAME} on ${HOST} ..."
ANSIBLE_HOST_KEY_CHECKING=False \
ansible-playbook -i "$TMP_INV" \
  "$SCRIPT_DIR/../ansible/playbooks/provision.yml" \
  --extra-vars \
  "github_owner=${OWNER} repo_name=${REPO} runner_name=${RUNNER_NAME} runner_user=${RUNNER_USER} runner_scope=${SCOPE} runner_group=${GROUP} runner_labels=${LABELS} registration_token=${TOKEN}"

rm -f "$TMP_INV"
echo "Done. Verify with: scripts/healthcheck.sh --owner ${OWNER} --repo ${REPO} --name ${RUNNER_NAME}"
