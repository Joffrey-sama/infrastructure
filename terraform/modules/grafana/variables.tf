variable "grafana_url" {
  description = "Grafana URL for API access"
  type        = string
}

variable "grafana_api_token" {
  description = "Grafana API token for provisioning"
  type        = string
  sensitive   = true
}

variable "prometheus_url" {
  description = "GreptimeDB URL for Prometheus metrics endpoint"
  type        = string
}

variable "greptimedb_pg_url" {
  description = "GreptimeDB PostgreSQL endpoint for SQL log queries (e.g. host:4003)"
  type        = string
  default     = ""
}

variable "loki_url" {
  description = "GreptimeDB URL for Loki logs endpoint (deprecated)"
  type        = string
  default     = ""
}

variable "oci_metrics_endpoint" {
  description = "OCI Monitoring metrics endpoint (optional)"
  type        = string
  default     = ""
}

variable "oci_logs_endpoint" {
  description = "OCI Logging endpoint (optional)"
  type        = string
  default     = ""
}

variable "grafana_folder_name" {
  description = "Grafana folder name for imported dashboards"
  type        = string
  default     = "Imported Dashboards"
}

variable "alertmanager_url" {
  type        = string
  description = "URL de l'instance Alertmanager"
  default     = "http://alertmanager.monitoring.svc.cluster.local:9093"
}

variable "import_dashboards" {
  description = "Map of dashboard names to their download URLs (e.g., Grafana API, GitHub raw)."
  type        = map(string)
}

variable "custom_dashboards" {
  description = "Map of custom dashboard names (slugs) to their raw JSON content."
  type        = map(string)
  default     = {}
}

variable "custom_folder_name" {
  description = "Grafana folder name for custom dashboards"
  type        = string
  default     = "Custom Dashboards"
}