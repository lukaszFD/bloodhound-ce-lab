#!/usr/bin/env bash
# Deploy the dev environment from the workstation:
# venv -> collections -> inventory -> YubiKey in ssh-agent -> ping -> bootstrap.yml -> site.yml
#
# Usage:
#   ./scripts/deploy-dev.sh                   # full run
#   ./scripts/deploy-dev.sh --skip-bootstrap  # site.yml only
#   ./scripts/deploy-dev.sh --check           # dry run (check mode, diff)
#
# Overrides (environment variables):
#   VENV=~/other_venv  PKCS11_LIB=/path/to/opensc-pkcs11.so  LIMIT=dev  NO_BECOME_PASS=1
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="${VENV:-$HOME/ansible_mint_venv}"
PKCS11_LIB="${PKCS11_LIB:-/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so}"
LIMIT="${LIMIT:-dev}"

SKIP_BOOTSTRAP=0
EXTRA_ARGS=()

for arg in "$@"; do
    case "${arg}" in
        --skip-bootstrap) SKIP_BOOTSTRAP=1 ;;
        --check) EXTRA_ARGS+=(--check --diff) ;;
        -h|--help)
            sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: ${arg}" >&2
            exit 1
            ;;
    esac
done

info() { echo -e "\033[1;34m[*]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[+]\033[0m $*"; }
fail() { echo -e "\033[1;31m[-]\033[0m $*" >&2; exit 1; }

# ansible.cfg is read from the current directory.
cd "${REPO_DIR}"

# 1. Python virtualenv with Ansible
info "Activating virtualenv: ${VENV}"
[[ -f "${VENV}/bin/activate" ]] || fail "Virtualenv not found at ${VENV} (set VENV=...)."
# shellcheck disable=SC1091
source "${VENV}/bin/activate"
command -v ansible-playbook >/dev/null || fail "ansible-playbook not found in ${VENV}."
ok "$(ansible --version | head -n1)"

# 2. Required collections (installed into ./collections, venv stays untouched)
if ! ansible-doc -t module community.general.timezone >/dev/null 2>&1; then
    info "Installing Ansible collections from requirements.yml..."
    ansible-galaxy collection install -r requirements.yml -p collections
fi
ok "Collections available."

# 3. Inventory
if [[ ! -f inventory/hosts.yml ]]; then
    fail "inventory/hosts.yml is missing. Run: cp inventory/hosts.yml.example inventory/hosts.yml and set the host IP."
fi
ok "Inventory: inventory/hosts.yml"

# 4. YubiKey in ssh-agent
set +e
ssh-add -l >/dev/null 2>&1
agent_rc=$?
set -e
if [[ ${agent_rc} -eq 2 ]]; then
    fail "No ssh-agent available. Start one with: eval \"\$(ssh-agent -s)\""
fi
[[ -f "${PKCS11_LIB}" ]] || fail "PKCS#11 library not found: ${PKCS11_LIB}"
# Read the public key from the token (no PIN needed) and look for it in the agent.
yubikey_pub="$(ssh-keygen -D "${PKCS11_LIB}" 2>/dev/null | awk 'NR==1 {print $2}')"
[[ -n "${yubikey_pub}" ]] || fail "No key found on the YubiKey. Is it plugged in?"
if ! ssh-add -L 2>/dev/null | grep -qF "${yubikey_pub}"; then
    info "Loading YubiKey into ssh-agent (PIV PIN required)..."
    ssh-add -s "${PKCS11_LIB}"
fi
ok "YubiKey loaded in ssh-agent."

# 5. Connectivity check (raw works even without Python on the target)
info "Checking connectivity to '${LIMIT}'..."
ansible "${LIMIT}" -m ansible.builtin.raw -a "echo ok" -o >/dev/null \
    || fail "Cannot reach '${LIMIT}' over SSH."
ok "Hosts reachable."

# 6. Sudo password for the target, asked once and shared by both playbooks
if [[ "${NO_BECOME_PASS:-0}" != "1" ]]; then
    BECOME_PASS_FILE="$(mktemp)"
    chmod 600 "${BECOME_PASS_FILE}"
    trap 'rm -f "${BECOME_PASS_FILE}"' EXIT
    read -r -s -p "Sudo password on target hosts: " become_pass
    echo
    printf '%s\n' "${become_pass}" > "${BECOME_PASS_FILE}"
    unset become_pass
    EXTRA_ARGS+=(--become-password-file "${BECOME_PASS_FILE}")
fi

# 7. Bootstrap bare Debian
if [[ ${SKIP_BOOTSTRAP} -eq 0 ]]; then
    info "Running bootstrap.yml..."
    ansible-playbook bootstrap.yml --limit "${LIMIT}" "${EXTRA_ARGS[@]}"
fi

# 8. Host preparation + Podman
info "Running site.yml..."
ansible-playbook site.yml --limit "${LIMIT}" "${EXTRA_ARGS[@]}"

ok "Dev deployment finished."
