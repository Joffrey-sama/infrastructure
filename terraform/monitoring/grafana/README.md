# Terraform Configuration for Grafana

This folder contains the Terraform configuration for managing Grafana datasources and dashboards for the monitoring stack.

## Project Structure

- `providers.tf` - Grafana provider configuration
- `variables.tf` - Variable definitions (environment-agnostic)
- `datasources.tf` - Datasource provisioning (GreptimeDB, OCI Monitoring, OCI Logs)
- `dashboards.tf` - Community dashboard imports
- `main.tf` - Outputs and backend config
- `terraform.tfvars.example` - Generic template for variable values
- `README.md` - This documentation

## Architecture

### Datasources
- **GreptimeDB** (Prometheus): Primary metrics collector for both OCI and on-prem environments via Alloy scrapers
- **OCI Monitoring** (optional): Native OCI metrics for billing, volume, IP monitoring, etc. Enabled via `oci_metrics_endpoint`
- **OCI Logging** (optional): Native OCI logs for audit trails and service logs. Enabled via `oci_logs_endpoint`

### Community Dashboards (Auto-imported)
Community dashboards are automatically fetched and provisioned from Grafana's dashboard library.

**Base Dashboards** (universal, always imported):

**Kubernetes & Infrastructure:**
- `1860` - Node Exporter for Prometheus (CPU, Memory, Disk, Network)
- `3119` - Kubernetes Cluster Monitoring
- `6417` - Kubernetes Kubelet
- `12114` - Kubernetes StatefulSets
- `6879` - Kubernetes Pod Monitoring
- `7249` - Kubernetes API Server

**Databases:**
- `9628` - PostgreSQL Database
- `11114` - Redis Dashboard

**Certificate Management:**
- `20842` - cert-manager

**Monitoring Infrastructure:**
- `3662` - Prometheus Targets
- `14694` - Grafana Alloy

**Extra Dashboards** (environment-specific, optional):
Can be defined in `terraform.tfvars.YOUR_ENVIRONMENT` via `extra_import_dashboards` variable. Examples:
- `13105` - OCI Monitoring
- `15357` - OCI Logs Analytics

## Configuration Flow

### 1. Generate Grafana API Token

```bash
# Via Grafana UI
# Settings → API Keys → Create New Key
# Copy token (only shown once)
```

### 2. Setup Environment Configuration

```bash
# Copy environment template for your environment
cp terraform.tfvars.example terraform.tfvars.YOUR_ENVIRONMENT

# Edit with your environment values
nano terraform.tfvars.YOUR_ENVIRONMENT
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Preview Changes

```bash
terraform plan \
  -var-file="terraform.tfvars.YOUR_ENVIRONMENT" \
  -var="grafana_api_token=$TF_VAR_GRAFANA_TOKEN"
```

### 5. Apply Configuration

```bash
terraform apply \
  -var-file="terraform.tfvars.YOUR_ENVIRONMENT" \
  -var="grafana_api_token=$TF_VAR_GRAFANA_TOKEN"
```

## Using Environment Variables

To avoid passing credentials on the command line:

```bash
export TF_VAR_grafana_api_token="your-api-token-here"
export TF_VAR_grafana_url="https://grafana.yourdomain.com"

# Now terraform commands don't need -var flags
terraform plan -var-file="terraform.tfvars.YOUR_ENVIRONMENT"
terraform apply -var-file="terraform.tfvars.YOUR_ENVIRONMENT"
```

## Available Variables

### Required Variables
| Variable | Description | Example |
|----------|-------------|---------|
| `grafana_url` | Grafana API endpoint URL | `https://grafana.yourdomain.com` |
| `grafana_api_token` | API token with admin permissions | `eyJrOiJRZWF3M...` |
| `greptimedb_url` | GreptimeDB Prometheus endpoint | `http://monitoring-greptimedb-standalone:4000` |

### Optional Variables
| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `grafana_folder_name` | Folder name for dashboards | `Imported Dashboards` | `Monitoring` |
| `oci_metrics_endpoint` | OCI Monitoring endpoint (enables OCI metrics) | `""` | `https://monitoring.eu-paris-1.oraclecloud.com` |
| `oci_logs_endpoint` | OCI Logging endpoint (enables OCI logs) | `""` | `https://logging.eu-paris-1.oraclecloud.com` |
| `Import_dashboards` | Dashboards | See below | `[1860, 3119, ...]` |

## File Organization

### Generic Files (Committed to Git)
- `providers.tf` - Provider configuration
- `variables.tf` - Variable definitions (no hardcoded values)
- `datasources.tf` - Datasource definitions
- `dashboards.tf` - Dashboard provisioning
- `main.tf` - Outputs and backend config
- `terraform.tfvars.example` - Generic template
- `.gitignore` - Excludes sensitive files
- `README.md` - This documentation

### Environment-Specific Files (Not Committed)
- `terraform.tfvars` - Your working copy (gitignored)
- `terraform.tfvars.*` - Environment-specific configs (gitignored for security)
- `terraform.tfstate*` - State files (gitignored)
- `.terraform/` - Provider cache (gitignored)

## State Management

Terraform state is stored locally in `terraform.tfstate` by default.

### Using Remote Backend (Recommended)

Configure a remote backend for better team collaboration (example using OCI):

```hcl
# main.tf
terraform {
  backend "s3" {
    bucket = "monitoring-terraform-state"
    key    = "monitoring/grafana/terraform.tfstate"
    region = "eu-paris-1"
    endpoint = "https://objectstorage.eu-paris-1.oraclecloud.com"
  }
}
```

Then migrate state:

```bash
terraform init  # Will prompt to migrate state
```

## Cleanup

To remove all Grafana resources managed by this configuration:

```bash
terraform destroy -var-file="terraform.tfvars.YOUR_ENVIRONMENT" \
                  -var="grafana_api_token=$TF_VAR_GRAFANA_TOKEN"
```

## Troubleshooting

### Error: "resource not authorized"
- Verify API token is valid
- Ensure token has Admin role
- Token may have expired (regenerate if needed)

### Dashboard not imported
- Check dashboard ID exists on [grafana.com/grafana/dashboards](https://grafana.com/grafana/dashboards)
- Run `terraform plan` to see detailed error messages
- Dashboard may require specific Grafana version

### OCI Datasources not connecting
- Verify endpoint URLs are correct and accessible
- Check IAM permissions for instance principal authentication
- Ensure OCI datasource plugins are installed in Grafana

### Datasource connection fails
- Verify GreptimeDB URL is accessible from Grafana pod: `curl <greptimedb_url>`
- Check GreptimeDB pod logs: `kubectl logs -f deployment/monitoring-greptimedb-standalone -n monitoring`
- Verify ingress/networking rules allow traffic

### Provider authentication issues
- Ensure `grafana_url` is correct (should be externally accessible from TF client)
- Test connectivity: `curl -H "Authorization: Bearer $TF_VAR_grafana_api_token" $TF_VAR_grafana_url/api/health`

## Next Steps

- [ ] Migrate to remote state backend (S3, OCI Object Storage, etc.)
- [ ] Add alerting rules and notification policies
- [ ] Configure Grafana folders and permissions via Terraform
- [ ] Integrate with CI/CD pipeline for automated updates
