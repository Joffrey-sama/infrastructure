# Terraform configuration for Grafana datasources and dashboards
# This module automatically provisions Grafana with:
# - GreptimeDB datasource for metrics
# - Community dashboards for comprehensive cluster monitoring

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

output "grafana_folder_id" {
  description = "Grafana folder ID for imported dashboards"
  value       = grafana_folder.imported.id
}

output "greptimedb_datasource_id" {
  description = "GreptimeDB datasource ID"
  value       = grafana_data_source.greptimedb.id
}

output "greptimedb_datasource_uid" {
  description = "GreptimeDB datasource UID for dashboard references"
  value       = grafana_data_source.greptimedb.uid
}

output "imported_dashboards" {
  description = "List of imported dashboard names and their source URLs."
  value       = var.import_dashboards
}

output "oci_metrics_datasource_id" {
  description = "OCI Monitoring datasource ID (if enabled)"
  value       = try(grafana_data_source.oci_metrics[0].id, null)
}

output "oci_logs_datasource_id" {
  description = "OCI Logs datasource ID (if enabled)"
  value       = try(grafana_data_source.oci_logs[0].id, null)
}
