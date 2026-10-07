# bhce-lab

Ansible project that prepares a lab host on Proxmox VE (Debian/Ubuntu) with **Podman** as the container runtime,
for testing BloodHound Community Edition (ITDR / IAM).

The repo prepares the host (packages, Podman, `podman-compose`, API socket). BloodHound CE itself is installed
with the official BloodHound CLI, following the SpecterOps quickstart.

## Structure

```
bhce-lab/
├── ansible.cfg
├── bootstrap.yml                # [00.x.x] bare Debian (dev): Python, tools, Ansible, Podman
├── site.yml                     # main playbook (dev + prod)
├── requirements.yml             # Ansible collections
├── inventory/
│   └── hosts.yml.example        # template - copy to hosts.yml (hosts.yml is git-ignored)
├── group_vars/
│   ├── lab.yml                  # shared variables
│   ├── dev.yml                  # dev: install packages
│   └── prod.yml                 # prod: Podman already present, packages untouched
├── scripts/
│   ├── deploy-dev.sh            # dev deployment from the workstation: venv, YubiKey, bootstrap + site
│   └── bootstrap-local.sh       # local bootstrap when the host has no Ansible
├── roles/
│   ├── host_prep/               # [01.x.x] base packages, timezone, /opt/lab directory
│   ├── podman/                  # [02.x.x] Podman, podman-compose, API socket, registries
│   └── app/                     # [03.x.x] placeholder for your own role
├── docs/
│   └── proxmox.md               # VM / LXC for Podman
└── .github/workflows/lint.yml   # yamllint + ansible-lint
```

## Requirements

| Where | What |
|---|---|
| Workstation | virtualenv with Ansible (default `~/ansible_mint_venv`), OpenSC (`opensc-pkcs11.so`), YubiKey with a key in PIV slot 9a |
| VM | Debian 13 / Ubuntu 24.04, 4 vCPU, **8 GB RAM** (ballooning disabled), 30 GB disk |

8 GB RAM is the minimum stated by SpecterOps - with less memory the `bloodhound` container
may exit with code 137 (OOM) right after startup.

In the examples below replace `<VM_IP>` with your VM address and `<SUDO_PASSWORD>` with the sudo password of the lab user.

## Step-by-step setup

### 1. VM on Proxmox

Create the VM as described in [docs/proxmox.md](docs/proxmox.md). Take a snapshot of the clean machine before continuing:

```bash
qm snapshot <vmid> clean-os
```

### 2. SSH login with YubiKey

On the workstation, export the public key from the YubiKey and copy it to the VM (first time with password):

```bash
mkdir -p ~/.ssh/yubikey
ssh-keygen -D /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so > ~/.ssh/yubikey/yubikey_9a.pub
ssh-keygen -l -f ~/.ssh/yubikey/yubikey_9a.pub
ssh-copy-id -f -i ~/.ssh/yubikey/yubikey_9a.pub hunter@<VM_IP>
```

Test the login and list the keys on the server:

```bash
ssh -I /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so hunter@<VM_IP>
ssh hunter@<VM_IP> "ssh-keygen -l -f ~/.ssh/authorized_keys"
```

Entry in `~/.ssh/config` (alias + tunnel to the BloodHound UI, see step 7):

```
Host bhce-dev
    HostName <VM_IP>
    User hunter
    PKCS11Provider /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
    IdentityFile ~/.ssh/yubikey/yubikey_9a.pub
    IdentitiesOnly yes
    LocalForward 8080 127.0.0.1:8080
```

After a successful test, disable password login (on the VM, keep a second session open):

```bash
sudo tee /etc/ssh/sshd_config.d/10-hardening.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF
sudo sshd -t && sudo systemctl reload ssh
ssh -o PubkeyAuthentication=no hunter@<VM_IP>   # must return Permission denied
```

### 3. Inventory

```bash
cp inventory/hosts.yml.example inventory/hosts.yml
```

Edit **`inventory/hosts.yml`** (not the `.example` file):

```yaml
---
all:
  children:
    lab:
      children:
        dev:
          hosts:
            dev-host:
              ansible_host: <VM_IP>
              ansible_user: hunter
              ansible_become_password: "<SUDO_PASSWORD>"   # lab only; this file is not committed
```

Check:

```bash
ansible-inventory --graph
ansible-inventory --host dev-host | grep become
```

### 4. Host preparation (Ansible)

```bash
chmod +x scripts/deploy-dev.sh
NO_BECOME_PASS=1 ./scripts/deploy-dev.sh           # full run: bootstrap.yml + site.yml
NO_BECOME_PASS=1 ./scripts/deploy-dev.sh --check   # dry run
NO_BECOME_PASS=1 ./scripts/deploy-dev.sh --skip-bootstrap
```

`NO_BECOME_PASS=1` - the sudo password is already in the inventory. Without it the script asks for it once.

The script activates the virtualenv, installs collections into `./collections`, loads the YubiKey into `ssh-agent`
(asks for the PIN if needed), checks connectivity, and runs `bootstrap.yml` and `site.yml` against the `dev` group.

Manual equivalent:

```bash
source ~/ansible_mint_venv/bin/activate
ssh-add -s /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
ansible dev -m ping
ansible-playbook bootstrap.yml
ansible-playbook site.yml -l dev
```

### 5. Rootless Podman for the user

BloodHound CLI run as `hunter` uses the user socket (`/run/user/1000/podman/podman.sock`),
not the system one. On the VM:

```bash
sudo loginctl enable-linger hunter            # containers keep running after logout and reboot
systemctl --user enable --now podman.socket
sudo touch /etc/containers/nodocker           # silences the "Emulate Docker CLI" message
docker version                                # Client + Server without errors = OK
loginctl show-user hunter -p Linger           # Linger=yes
```

Snapshot of the prepared host:

```bash
qm snapshot <vmid> podman-ready
```

### 6. BloodHound CE

Install it following the official SpecterOps quickstart (BloodHound CLI), as user `hunter` on the VM.
After installation the UI listens only on `127.0.0.1:8080` on the VM - access it from the workstation through an SSH tunnel (step 7).
The admin password is returned by `bloodhound-cli config get default_password`.

### 7. UI access from the workstation (SSH tunnel)

```bash
ssh -N -L 8080:127.0.0.1:8080 hunter@<VM_IP>
```

or with the alias from step 2:

```bash
ssh -N bhce-dev
```

The terminal "hangs" without output - that is expected (`-N` = tunnel only). Keep it open and browse to:

```
http://localhost:8080/ui/login
```

Login: `admin` (default e-mail: `admin@example.com`). Set a new password on first login.
If port 8080 is busy on the workstation: `-L 18080:127.0.0.1:8080` and `http://localhost:18080/ui/login`.

Troubleshooting:

```bash
ss -ltn | grep 8080                                                  # workstation: is the tunnel listening
ssh hunter@<VM_IP> "curl -sI http://127.0.0.1:8080/ui/login | head -1"   # VM: HTTP/1.1 200 OK
ssh hunter@<VM_IP> "podman ps -a"                                    # VM: container status
```

## Dev vs prod

| Environment | Starting point | What to run |
|---|---|---|
| **dev** | bare Debian, no Ansible or Podman | `bootstrap.yml`, then `site.yml` (or `deploy-dev.sh`) |
| **prod** | Podman and Ansible already installed | `site.yml` only (`podman_install_packages: false`) |

```bash
ansible-playbook site.yml -l prod
```

On prod the `podman` role does not install packages - it only checks that `podman` exists
and applies configuration (registries, socket, `podman-restart`).

### Local bootstrap (on the host itself, without a workstation)

```bash
apt-get update && apt-get install -y git
git clone https://github.com/<your-login>/bhce-lab.git /opt/bhce-lab
cd /opt/bhce-lab
sudo ./scripts/bootstrap-local.sh --with-site
```

## Variables (group_vars/lab.yml)

| Variable | Default | Description |
|---|---|---|
| `host_prep_app_base_dir` | `/opt/lab` | application directory |
| `host_prep_timezone` | `Europe/Warsaw` | timezone |
| `podman_install_packages` | `true` (prod: `false`) | whether the role installs Podman packages |
| `podman_enable_socket` | `true` | system API socket at `/run/podman/podman.sock` |
| `podman_install_docker_shim` | `true` | `podman-docker` package (`docker` command -> Podman) |
| `podman_compose_from_pip` | `false` | latest `podman-compose` from PyPI instead of apt |

## Known notes

- The user socket and linger (step 5) are manual for now - the `podman` role only enables the system socket.
- `deploy-dev.sh` uses `ansible -o` in the connectivity check, which prints `DEPRECATION WARNING`
  messages on ansible-core 2.19 - harmless.
- `hosts.yml.example` is committed - keep placeholder values in it, never real IPs or passwords.