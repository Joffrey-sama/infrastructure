# Changelog - joffrey_sama.infrastructure

All notable changes to the `joffrey_sama.infrastructure` Ansible collection will be documented in this file.

## [1.1.4] - 2026-08-14
- Condition control node kubeconfig configuration with k3s_configure_control_node variable.

## [1.1.3] - 2026-08-08
- Fix dynamic become inheritance on control node tasks delegated to localhost (roles/k3s).

## [1.0.0] - 2026-07-22
- Initial release of the `joffrey_sama.infrastructure` Ansible collection.
- Added roles: `common`, `ipsec`, `k3s`, `storage`.
- Added playbooks: `setup.yml`, `setup-ipsec.yml`, `backup.yml`, `restart-k3s.yml`, `update-k3s.yml`.
