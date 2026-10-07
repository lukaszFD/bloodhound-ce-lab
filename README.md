# BloodHound Community Edition - Ansible Deployment

Automated Ansible playbook to deploy **BloodHound Community Edition (BHCE)** using Docker Compose, pre-configured for external network accessibility and test environment readiness.

## Features
- **Automated Infrastructure Setup**: Full provisioning of Docker CE and Docker Compose plugin on Debian-based hosts.
- **BloodHound CE Service Stack**: Configures and starts PostgreSQL, Neo4j, and BloodHound API/UI containers.
- **Network Access**: Pre-configured environment settings (`BLOODHOUND_HOST=0.0.0.0`) for seamless web UI access.
- **Sample Data Ingestion**: Python automation scripts to ingest sample Active Directory and Entra ID (Azure AD) datasets for threat analysis testing.
