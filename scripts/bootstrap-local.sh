#!/usr/bin/env bash
# Bootstrap a bare Debian host locally: install Ansible from apt,
# then run bootstrap.yml and site.yml against localhost.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (sudo $0)." >&2
    exit 1
fi

if ! grep -qiE '^ID(_LIKE)?=.*debian' /etc/os-release; then
    echo "This script supports Debian/Ubuntu only." >&2
    exit 1
fi

echo "[*] Installing Ansible and Git from apt..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ansible git python3-apt

cd "${REPO_DIR}"

echo "[*] Installing Ansible collections..."
ansible-galaxy collection install -r requirements.yml -p collections

INVENTORY="localhost,"
COMMON_ARGS=(-i "${INVENTORY}" -c local -e bootstrap_target=all)

echo "[*] Running bootstrap.yml..."
ansible-playbook "${COMMON_ARGS[@]}" bootstrap.yml

if [[ "${1:-}" == "--with-site" ]]; then
    echo "[*] Running site.yml..."
    ansible-playbook "${COMMON_ARGS[@]}" -e lab_target=all site.yml
fi

echo "[+] Done."
