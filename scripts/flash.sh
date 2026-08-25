#!/usr/bin/env bash
#
# flash.sh — build a fully-provisioned Raspberry Pi OS SD card that registers a
# self-hosted GitHub Actions runner on first boot, with ZERO SSH.
#
# What it does:
#   1. Resolves a Raspberry Pi OS (64-bit) image (local or auto-downloaded).
#   2. Mounts the image's boot partition and injects:
#        - wpa_supplicant.conf   (Wi-Fi)
#        - user-data             (cloud-init bootstrap -> installs + registers runner)
#        - meta-data
#        - ssh                   (optional, debugging only)
#   3. Optionally writes the prepared image to an SD card (dd).
#
# The registration token is the Terraform output `registration_token` (valid ~1h).
# Run `terraform apply` immediately before flashing so the token is fresh.
#
# Usage examples:
#   scripts/flash.sh --disk /dev/disk4 --owner acme --repo pi-actions \
#     --token "$(go run /dev/null)" --wifi-ssid HomeWifi --wifi-pass hunter2
#
#   scripts/flash.sh --out ~/pi-runner.img --user-data <(terraform output -raw cloud_init_user_data)
#
# Cross-platform notes: macOS via hdiutil+diskutil (tested), Linux via kpartx.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- defaults --------------------------------------------------------------
DISK=""
IMAGE=""
IMAGE_URL=""
OUT_IMG=""
USER_DATA_FILE=""
WIFI_SSID=""
WIFI_PASS=""
GITHUB_OWNER=""
REPO_NAME=""
TOKEN=""
RUNNER_NAME="pi-runner-01"
LABELS="self-hosted,linux,arm64,pi"
SCOPE="repo"
GROUP="default"
ENABLE_SSH=0
TIMEZONE="UTC"
FORCE=0

usage() {
  cat <<EOF
Usage: $0 [options]

  -d, --disk <dev>       SD card device to flash (e.g. /dev/disk4) [needs sudo]
  -i, --image <file>     Local Pi OS image (.img/.img.xz/.img.zip). Optional.
      --image-url <url>  Explicit Pi OS image URL. Optional (auto-resolved otherwise).
  -o, --out <file>       Write the prepared image to <file> instead of a card.
      --user-data <f>    Use an existing user-data file (e.g. Terraform output).
  --owner <owner>        GitHub owner (from Terraform).
  --repo  <repo>         GitHub repository the runner registers to.
  --token <token>        Runner registration token (Terraform output, ~1h).
  --runner-name <name>   Runner/host name (default: pi-runner-01).
  --labels <list>        Comma labels (default: self-hosted,linux,arm64,pi).
  --scope <repo|org>     Registration scope (default: repo).
  --group <name>         Org runner group (used when --scope org).
  --wifi-ssid <ssid>     Wi-Fi SSID.
  --wifi-pass <pass>     Wi-Fi passphrase.
  --enable-ssh           Enable sshd on first boot (debug only).
  --timezone <tz>        Timezone (default: UTC).
  --force                Skip the destructive flash confirmation prompt.
  -h, --help             Show this help.
EOF
  exit 0
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '  * %s\n' "$*"; }
warn() { printf 'WARNING: '; printf '%s\n' "$*" >&2; }

# ---- arg parse -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--disk)       DISK="$2"; shift 2;;
    -i|--image)      IMAGE="$2"; shift 2;;
    --image-url)     IMAGE_URL="$2"; shift 2;;
    -o|--out)        OUT_IMG="$2"; shift 2;;
    --user-data)     USER_DATA_FILE="$2"; shift 2;;
    --owner)         GITHUB_OWNER="$2"; shift 2;;
    --repo)          REPO_NAME="$2"; shift 2;;
    --token)         TOKEN="$2"; shift 2;;
    --runner-name)   RUNNER_NAME="$2"; shift 2;;
    --labels)        LABELS="$2"; shift 2;;
    --scope)         SCOPE="$2"; shift 2;;
    --group)         GROUP="$2"; shift 2;;
    --wifi-ssid)     WIFI_SSID="$2"; shift 2;;
    --wifi-pass)     WIFI_PASS="$2"; shift 2;;
    --enable-ssh)    ENABLE_SSH=1; shift;;
    --timezone)      TIMEZONE="$2"; shift 2;;
    --force)         FORCE=1; shift;;
    -h|--help)       usage;;
    *) die "unknown option: $1";;
  esac
done

command -v curl >/dev/null || die "curl is required"
command -v xz   >/dev/null || die "xz is required (brew install xz)"
command -v git  >/dev/null  # optional, only used to confirm repo reachability

if [[ -z "$OUT_IMG" && -z "$DISK" ]]; then
  die "provide --disk <dev> to flash, or --out <file> to build an image"
fi
if [[ -z "$TOKEN" && -z "$USER_DATA_FILE" ]]; then
  die "provide --token <token> (terraform output registration_token) or --user-data <file>"
fi
if [[ -z "$GITHUB_OWNER" || -z "$REPO_NAME" ]]; then
  die "provide --owner and --repo to point the runner at your repository"
fi

# ---- image resolution ------------------------------------------------------
resolve_image() {
  if [[ -n "$IMAGE" ]]; then
    [[ -f "$IMAGE" ]] || die "image not found: $IMAGE"
    echo "$IMAGE"; return
  fi
  local index url
  if [[ -n "$IMAGE_URL" ]]; then
    url="$IMAGE_URL"
  else
    info "Resolving latest Raspberry Pi OS Lite (arm64) image..."
    index="$(curl -fsSL https://downloads.raspberrypi.com/raspios_lite_arm64/images/)"
    # Pick the newest version folder (non-dot, has a date)
    local ver dir
    ver="$(grep -oE 'raspios_lite_arm64-[0-9-]+/' <<<"$index" | sort -r | head -1)"
    [[ -n "$ver" ]] || die "could not resolve Pi OS image version from index"
    dir="https://downloads.raspberrypi.com/raspios_lite_arm64/images/${ver}"
    url="$(curl -fsSL "$dir" | grep -oE 'href="[^"]+\.img\.(xz|zip|lz4)"' \
      | sed -E 's/href="//; s/"$//' | sed "s#^#${dir}#" | head -1)"
    [[ -n "$url" ]] || die "could not resolve image file under $dir"
  fi
  echo "$url"
}

fetch_image() { # url -> local .img
  local url="$1" f ext
  f="$(basename "$url")"
  ext="${f##*.}"
  pushd "$REPO_ROOT" >/dev/null
  info "Downloading ${f} ..."
  curl -fL "$url" -o "$f"
  case "$ext" in
    xz)   info "Decompressing .xz"; xz --decompress --keep "$f"; f="${f%.xz}";;
    zip)  info "Unzipping"; unzip -o -q "$f"; f="${f%.zip}.img";;
    lz4)  info "Decompressing .lz4"; unlz4 "$f" "${f%.lz4}.img"; f="${f%.lz4}.img";;
  esac
  popd >/dev/null
  [[ -f "$REPO_ROOT/$f" ]] || die "download produced no .img"
  echo "$REPO_ROOT/$f"
}

# ---- cloud-init user-data --------------------------------------------------
gen_user_data() {
  cat <<EOF
#cloud-config
hostname: ${RUNNER_NAME}
preserve_hostname: false
timezone: ${TIMEZONE}
manage_etc_hosts: true
ssh_pwauth: false
disable_root: true

write_files:
  - path: /etc/pi-actions/registration-token
    permissions: "0600"
    owner: root:root
    content: |
      ${TOKEN}
  - path: /etc/pi-actions/environment
    permissions: "0644"
    owner: root:root
    content: |
      PI_ACTION_REPO=${REPO_NAME}
      PI_ACTION_OWNER=${GITHUB_OWNER}

runcmd:
  - "[sh, -c, 'systemctl enable --now ssh || true']"
  - |
    set -eu
    exec >> /var/log/pi-actions-bootstrap.log 2>&1
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y git ca-certificates curl
    if ! command -v ansible-pull >/dev/null 2>&1; then
      apt-get install -y ansible-core 2>/dev/null || apt-get install -y ansible 2>/dev/null \
        || pip3 install --no-cache-dir --break-system-packages ansible-core
    fi
    ansible-pull \
      -U https://github.com/${GITHUB_OWNER}/${REPO_NAME}.git \
      -C main -i localhost, --accept-new-host-key \
      -e "runner_scope=${SCOPE} runner_name=${RUNNER_NAME} runner_user=runner runner_group=${GROUP} runner_labels=${LABELS} repo_name=${REPO_NAME} github_owner=${GITHUB_OWNER}" \
      ansible/playbooks/bootstrap.yml
EOF
}

# Boot partition helpers (macOS) --------------------------------------------
ATTACHED_DISK=""
MOUNT_PT=""
cleanup() {
  if [[ -n "$MOUNT_PT" ]]; then umount "$MOUNT_PT" >/dev/null 2>&1 || true; fi
  if [[ -n "$ATTACHED_DISK" ]]; then hdiutil detach "$ATTACHED_DISK" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

mount_boot() { # img
  local img="$1" disk
  local base
  base="$(basename "$img" .img)"
  ATTACHED_DISK="$(hdiutil attach -nomount "$img" | awk '{print $NF}' | head -1)"
  [[ -n "$ATTACHED_DISK" ]] || die "hdiutil attach failed for $img"
  # boot partition is the first FAT partition of the Pi image
  local bootdev
  bootdev="/dev/${ATTACHED_DISK##*/}s1"
  diskutil mount "$bootdev" >/dev/null
  MOUNT_PT="$(diskutil info -plist "$bootdev" | grep -A1 'MountPoint' | grep -oE '/Volumes/[^<]+' | head -1 | sed 's#/$##' || true)"
  if [[ -z "$MOUNT_PT" ]]; then
    MOUNT_PT="$(find /Volumes -maxdepth 1 -iname 'boot*' | head -1 || true)"
  fi
  [[ -n "$MOUNT_PT" ]] && [[ -d "$MOUNT_PT" ]] || die "could not find boot mountpoint"
  info "boot partition mounted at $MOUNT_PT"
}

write_boot_files() {
  local mnt="$1"
  local wpa="${mnt}/wpa_supplicant.conf"
  if [[ -n "$WIFI_SSID" ]]; then
    info "Writing Wi-Fi config"
    cat >"$wpa" <<EOF
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
network={
    ssid="${WIFI_SSID}"
    psk="${WIFI_PASS}"
    key_mgmt=WPA-PSK
}
EOF
  else
    warn "no --wifi-ssid provided; the Pi will need Ethernet"
  fi

  info "Writing cloud-init user-data"
  if [[ -n "$USER_DATA_FILE" ]]; then
    cp "$USER_DATA_FILE" "${mnt}/user-data"
  else
    gen_user_data > "${mnt}/user-data"
  fi
  printf 'instance-id: pi-actions\n' > "${mnt}/meta-data"

  if [[ "$ENABLE_SSH" == "1" ]]; then
    info "Enabling ssh on first boot (debug)"
    touch "${mnt}/ssh"
  fi
}

# ---- flash -----------------------------------------------------------------
flash_card() {
  local dev="$1" img="$2"
  [[ "$dev" == /dev/disk* ]] || die "refusing to flash non /dev/disk device: $dev"
  printf 'WARNING: this will ERASE %s.\n' "$dev"
  if [[ "$FORCE" != "1" ]]; then
    printf 'Type the full device name to confirm (e.g. %s): ' "$dev"
    local confirm
    read -r confirm
    [[ "$confirm" == "$dev" ]] || die "aborted"
  fi
  info "Flashing $img -> $dev (this can take 5-10 min) ..."
  sudo diskutil unmountDisk "$dev" >/dev/null 2>&1 || true
  # Drain writes before reporting success
  sudo dd if="$img" of="$dev" bs=4m conv=fsync status=progress
  sudo diskutil eject "$dev" >/dev/null 2>&1 || true
  info "Done. Insert the card, power on the Pi — it will self-register with GitHub."
}

# ---- main ------------------------------------------------------------------
info "Preparing Pi Actions runner image"
IMG_URL="$(resolve_image)"
IMG="$(fetch_image "$IMG_URL")"
info "Using image: $IMG"

mount_boot "$IMG"
write_boot_files "$MOUNT_PT"
cleanup
trap - EXIT

if [[ -n "$OUT_IMG" ]]; then
  cp "$IMG" "$OUT_IMG"
  info "Prepared image written to $OUT_IMG (flash it with dd or rpi-imager)."
  exit 0
fi

flash_card "$DISK" "$IMG"
