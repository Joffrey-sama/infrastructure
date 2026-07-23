# Server Configuration Project

This project contains Ansible playbooks and roles for setting up and managing a Kubernetes (K3s) cluster on WSL2, designed to be extended later for a dedicated server.

## Prerequisites

- WSL2 with Ubuntu/Debian (with systemd enabled)
- Python 3.x
- Ansible 2.9+

## Project Structure

```
server-config/
├── playbooks/           # Ansible playbooks
│   ├── setup-wsl.yml    # Initial WSL setup
│   ├── update-k3s.yml   # K3s update procedure
│   └── backup.yml       # Backup configuration
├── inventory/
│   ├── group_vars/      # Environment variables
│   │   └── wsl.yml      # WSL specific variables
│   └── hosts.yml        # Ansible inventory
└── roles/              # Ansible roles
    ├── common/         # System configuration
    ├── k3s/           # K3s installation
    └── storage/        # Storage setup
```

## Configuration

The main configuration variables are stored in `inventory/group_vars/wsl.yml`:

- `k3s_version`: Version of K3s to install
- `storage_path`: Base path for K3s storage
- `system_packages`: List of required system packages

## Usage

### Initial Setup

```bash
# Install required Ansible collections
ansible-galaxy collection install community.general

# Run the initial setup
ansible-playbook playbooks/setup-wsl.yml -i inventory/hosts.yml
```

### Update K3s

```bash
ansible-playbook playbooks/update-k3s.yml -i inventory/hosts.yml
```

### Backup Configuration

```bash
ansible-playbook playbooks/backup.yml -i inventory/hosts.yml
```

## Features

- 🚀 Automated K3s installation and configuration
- 📦 System dependencies management
- 💾 Persistent storage configuration
- 🔄 K3s update management
- 💾 Backup functionality

## Notes

- WSL2 will be configured to use systemd during initial setup
- A WSL restart may be required after initial setup
- Storage paths are configured for WSL2 filesystem
- System parameters are tuned for containerized workloads

## License

MIT

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request