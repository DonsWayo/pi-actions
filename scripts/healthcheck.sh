#!/usr/bin/env bash
#
# healthcheck.sh — poll GitHub for the self-hosted runner's status.
#
# Usage:
#   scripts/healthcheck.sh --owner acme --repo pi-actions          # watch a runner
#   scripts/healthcheck.sh --owner acme --repo pi-actions --once  # single check
#
# Exit codes: 0 = runner online, 2 = offline/not registered.

set -euo pipefail

OWNER=""
REPO=""
NAME="pi-runner-01"
ONCE=0
INTERVAL=20
MAX_WAIT=1200          # 20 min (bootstrap ~ installs + registers)

usage() {
  cat <<EOF
Usage: $0 --owner <owner> --repo <repo> [--name <runner>] [--once] [--every <s>] [--timeout <s>]
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)   OWNER="$2"; shift 2;;
    --repo)    REPO="$2"; shift 2;;
    --name)    NAME="$2"; shift 2;;
    --once)    ONCE=1; shift;;
    --every)   INTERVAL="$2"; shift 2;;
    --timeout) MAX_WAIT="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "unknown: $1" >&2; exit 1;;
  esac
done

command -v gh >/dev/null || { echo "gh CLI is required" >&2; exit 1; }
[[ -n "$OWNER" && -n "$REPO" ]] || { echo "--owner and --repo are required" >&2; exit 1; }
gh auth status >/dev/null || { echo "run: gh auth login" >&2; exit 1; }

deadline=$(( $(date +%s) + MAX_WAIT ))
online=""

while true; do
  runners="$(gh api "repos/${OWNER}/${REPO}/actions/runners" --jq '.runners' 2>/dev/null || echo '[]')"
  status="$(echo "$runners" | jq -r --arg n "$NAME" '.[] | select(.name == $n) | .status' 2>/dev/null || true)"

  if [[ -z "$status" ]]; then
    echo "[$(date +%T)] $NAME: not registered yet (bootstrap running?)"
  else
    echo "[$(date +%T)] $NAME: $status"
    if [[ "$status" == "online" ]]; then online=1; break; fi
  fi

  [[ "$ONCE" == "1" ]] && { [[ "$online" == "1" ]] && exit 0 || exit 2; }
  [[ $(date +%s) -ge "$deadline" ]] && { echo "Timed out waiting for runner to come online" >&2; exit 2; }
  sleep "$INTERVAL"
done

exit 0
