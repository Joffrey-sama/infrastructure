# GreptimeDB Datasource for Prometheus metrics collection
# Unified datasource for both OCI and on-prem environments
# Metrics are pushed by Alloy scrapers
resource "grafana_data_source" "greptimedb" {
  name        = "GreptimeDB"
  type        = "prometheus"
  url         = var.prometheus_url
  is_default  = true
  access_mode = "proxy"
  json_data_encoded = jsonencode({
    httpMethod   = "GET"
    timeInterval = "30s"
  })
}

# Logs datasource for GreptimeDB (Loki)
resource "grafana_data_source" "greptimedb_logs" {
  name        = "GreptimeDB Logs"
  type        = "loki"
  url         = var.loki_url
  access_mode = "proxy"

  json_data_encoded = jsonencode({
    maxLines = 1000
  })
}

# OCI Monitoring Datasource (optional, for monitoring metrics)
resource "grafana_data_source" "oci_metrics" {
  count       = var.oci_metrics_endpoint != "" ? 1 : 0
  name        = "OCI Monitoring"
  type        = "oci-metrics-datasource"
  url         = var.oci_metrics_endpoint
  is_default  = false
  access_mode = "proxy"
  json_data_encoded = jsonencode({
    authType = "instance_principal"
  })
}

# OCI Logging Datasource (optional, for log analysis)
resource "grafana_data_source" "oci_logs" {
  count       = var.oci_logs_endpoint != "" ? 1 : 0
  name        = "OCI Logs"
  type        = "oci-logs-datasource"
  url         = var.oci_logs_endpoint
  is_default  = false
  access_mode = "proxy"
  json_data_encoded = jsonencode({
    authType = "instance_principal"
  })
}

# Alertmanager Datasource
resource "grafana_data_source" "alertmanager" {
  name        = "Alertmanager"
  type        = "alertmanager"
  url         = var.alertmanager_url
  access_mode = "proxy"
  json_data_encoded = jsonencode({
    implementation = "prometheus"
  })
}
