# Infrastructure

[![Ansible CI/CD](https://github.com/Joffrey-sama/infrastructure/actions/workflows/ansible.yml/badge.svg)](https://github.com/Joffrey-sama/infrastructure/actions/workflows/ansible.yml)
[![Helm CI/CD](https://github.com/Joffrey-sama/infrastructure/actions/workflows/helm.yml/badge.svg)](https://github.com/Joffrey-sama/infrastructure/actions/workflows/helm.yml)
[![Terraform CI/CD](https://github.com/Joffrey-sama/infrastructure/actions/workflows/terraform.yml/badge.svg)](https://github.com/Joffrey-sama/infrastructure/actions/workflows/terraform.yml)
[![Workflows CI/CD](https://github.com/Joffrey-sama/infrastructure/actions/workflows/ci.yml/badge.svg)](https://github.com/Joffrey-sama/infrastructure/actions/workflows/ci.yml)

A collection of reusable, environment-agnostic Infrastructure as Code (IaC) resources. This repository serves as a centralized hub for public configurations, templates, and packages used across various Kubernetes clusters and environments.

## 📁 Repository Structure

* **`kubernetes/`**: 
  * `charts/`: Public Helm charts (Servarr stack, AdGuard Home, VPN routing, database tools, etc.).
  * `manifests/`: Base and sample resource definitions.
* **`ansible/`**: Common roles, collections, and server configuration playbooks.
* **`terraform/`**: Reusable modules for cloud providers and cluster provisioning.

## 🔒 Security & Privacy
This repository is **completely environment-agnostic** and contains **no secrets, private keys, or credentials**. Production overrides, cluster states, and private values are maintained in a separate private GitOps repository.
