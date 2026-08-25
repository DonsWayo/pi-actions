# 🍓 pi-actions

Run **GitHub Actions on a Raspberry Pi** — fully bootstrapped by infrastructure-as-code.
Insert the card, power on, and the Pi registers itself as a self-hosted Actions
runner. **No SSH. No manual login. Zero-config first boot.**

```
┌─────────┐   terraform apply    ┌────────────┬──────────────┐
│   your  │ ───────────────────▶ │  GitHub    │ short-lived  │
│ laptop  │                      │  repo +    │ registration │
│         │                      │  runner    │  token (~1h) │
└────┬────┘                      └────────────┴──────┬───────┘
     │ flash.sh writes SD card:                      │
     │   Pi OS image + wpa_supplicant + user-data    │
     │   (cloud-init carries the token)              │
     ▼                                               │
┌─────────────┐  first boot  ┌──────────────────────┐│
│   SD card   │─────────────▶│  Pi runs cloud-init  ││
│  insert +   │              │  -> ansible-pull     ││
│   power on  │              │  -> config.sh registers (burned token)
└─────────────┘              │  -> systemd starts runner
                             └──────────────────────┘
```

## What's inside

| Layer | Path | Purpose |
|-------|------|---------|
| **Terraform** | `terraform/` | GitHub repo, org runner group, runner labels, **registration token**, cloud-init `user-data` generation |
| **Ansible** | `ansible/` | `base` + `github-runner` roles: installs the arm64 runner, registers it, installs a systemd unit so it auto-starts |
| **Cloud-init** | `cloud-init/` + generated | First-boot bootstrap (Wi-Fi, hostname, ssh toggle, `ansible-pull`) |
| **Scripts** | `scripts/` | `flash.sh` (build/flash card), `get-token.sh`, `healthcheck.sh`, `register.sh` |
| **Workflows** | `.github/workflows/` | Sample job that runs on `[self-hosted, linux, arm64, pi]` |
| **Makefile** | `Makefile` | Convenience targets |

## Requirements

- Raspberry Pi **4 / 5** (arm64) — Pi OS 64-bit
- A **microSD card** (≥ 16 GB)
- Tools on your laptop:
  - `terraform` ≥ 1.5
  - `gh` CLI (authenticated: `gh auth login`)
  - `curl`, `xz`
  - `ansible` (only needed for the SSH provision path)
  - macOS: `hdiutil`/`diskutil` (built in) — Linux: `kpartx`
- A GitHub token exported as `GITHUB_TOKEN`. Minimum scopes:
  - `repo` (create/manage the repo + registration token)
  - `admin:org` (only if you register into an **org** runner group)

## Quick start (the zero-SSH path)

```bash
# 1. Configure
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in owner/repo
export GITHUB_TOKEN=ghp_xxxxxxxx              # token from step 1 above

# 2. Provision GitHub side + produce a FRESH registration token (valid ~1h)
terraform init && terraform apply
TOKEN="$(terraform output -raw registration_token)"
```

```bash
# 3. Build & flash the SD card (do this within the hour)
../scripts/flash.sh \
  --disk /dev/disk4 \
  --owner <owner> --repo <repo> \
  --token "$TOKEN" \
  --wifi-ssid "MyNetwork" --wifi-pass "hunter2" \
  --runner-name pi-runner-01
```

> ⚠️ The registration token expires in ~1 hour. Run `terraform apply` (or
> `scripts/get-token.sh`) right before flashing. If it lapses, rerun and re-flash
> — you can reuse the same card and image.

```bash
# 4. Insert the card, connect power/Ethernet (or Wi-Fi), wait.
#    The Pi boots, flashes its own LEDs, and:
#      - cloud-init enables the network
#      - ansible-pull clones THIS repo and applies the runner role
#      - config.sh registers into your repo using the burned-in token
#      - systemd starts the runner (auto-restarts on failure)

# 5. Watch for it to come online (no SSH needed)
../scripts/healthcheck.sh --owner <owner> --repo <repo> --name pi-runner-01
#  -> pi-runner-01: online
```

```bash
# 6. Prove it works — run the smoke test workflow
#    dispatch:  gh workflow run pi-runner.yml --repo <owner>/<repo>
#    or trigger on a push to main. The job runs ON THE PI.
```

## Reprovision / reconfigure an existing Pi (over SSH)

Useful if the first boot half-finished, you changed labels, or you'd rather manage
the device over SSH.

```bash
scripts/register.sh \
  --owner <owner> --repo <repo> --host 192.168.1.50 \
  --runner-name pi-runner-01 --user runner
```

This refreshes a token, generates a temp inventory, and runs
`ansible/playbooks/provision.yml`. You can also run Ansible directly:

```bash
cd ansible
ansible-playbook -i inventory.yml --ask-become-pass playbooks/provision.yml \
  -e "github_owner=<owner> repo_name=<repo> runner_name=pi-runner-01"
```

## Registry & runner details

- **Scopes**: `runner_scope = "repo"` (default) registers the runner against one
  repo. `runner_scope = "org"` registers it at the org level and, if
  `runner_group` is set, places it in a dedicated runner group.
- **Labels**: the runner presents `self-hosted`, `linux`, `arm64` plus any you add
  in `runner_labels`. Jobs must declare matching `runs-on` labels.
- **Service**: `actions.runner.<name>.service` — starts on boot, `Restart=always`.
- **Log on the Pi**: `journalctl -u actions.runner.<name> -f` (if you enable SSH);
  bootstrap progress: `cat /var/log/pi-actions-bootstrap.log`.

## Security (important)

Self-hosted runners on a **public** repository are reachable by **anyone**. A
malicious PR can run code on a **private home device**. Mitigations:

1. Keep the repo **private**, or
2. Scope the runner to a **private** repo, and
3. Restrict workflow triggers to trusted branches/paths (see `.github/`),
4. Run the runner as a **low-privilege** `runner` user (the role does this),
5. Consider the runner group + runner group's "allowed repositories" setting,
6. Review every incoming PR before it touches `:.github/`.

Follow GitHub's official guidance: <https://docs.github.com/actions/security-for-github-actions/security-hardening-for-github-actions>

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `boot` partition has no `user-data` | Flash with `--out <file>` then inspect; ensure your card is not mounted elsewhere |
| Runner never appears | Check the token: it expires in ~1h. Re-run `get-token.sh`, re-flash |
| Bootstrap fails on the Pi | Enable SSH (`--enable-ssh`), then read `/var/log/pi-actions-bootstrap.log` |
| Runner offline after boot | `systemctl status actions.runner.<name>` and the runner logs |
| `runs-on` never picks the Pi | Labels must match exactly — compare `runner_labels` (Terraform) with the job's `runs-on` |

## Roadmap / ideas

- [ ] GitHub Actions via a **code-signing host** for release binaries
- [ ] Nightly runner self-update timer
- [ ] Multi-runner fleet (`runner_name` per device)
- [ ] Git LFS mirror / Docker cache node
- [ ] Tailscale/WireGuard overlay so the Pi is reachable without a public IP

## License

MIT — see [`LICENSE`](LICENSE).
