# BloodHound Community Edition - Ansible & Podman Deployment

Automated Ansible playbook to deploy **BloodHound Community Edition (BHCE)** using **Podman** and **Podman Compose**, pre-configured for external network accessibility and threat analysis testing.

## Features
- **Automated Infrastructure Setup**: Full provisioning of Podman and `podman-compose` on Debian-based hosts.
- **BloodHound CE Service Stack**: Configures and runs PostgreSQL, Neo4j, and BloodHound API/UI containers in a daemonless, containerized environment.
- **Network Access**: Pre-configured environment settings (`BLOODHOUND_HOST=0.0.0.0`) for seamless web UI access.
- **Sample Data Ingestion**: Python automation scripts to ingest sample Active Directory and Entra ID (Azure AD) datasets for threat intelligence analysis.
