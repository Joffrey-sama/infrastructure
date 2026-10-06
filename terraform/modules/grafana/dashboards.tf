# Grafana folder for imported community dashboards
resource "grafana_folder" "imported" {
  title = var.grafana_folder_name
}

locals {
  # Precise mapping of common community dashboard variables to our UIDs.
  # Standard Grafana variable names are used as keys.
  dashboard_replacements = {
    "$${DS_PROMETHEUS}"  = grafana_data_source.greptimedb.uid
    "$${datasource}"     = grafana_data_source.greptimedb.uid
    "$${DS_LOGS}"        = grafana_data_source.greptimedb_logs.uid
    "$${DS_OCI_METRICS}" = try(grafana_data_source.oci_metrics[0].uid, "")
    "$${DS_OCI_LOGS}"    = try(grafana_data_source.oci_logs[0].uid, "")
  }
}

# Fetch community dashboards from Grafana marketplace via HTTP API
data "http" "dashboard_json" {
  for_each = var.import_dashboards
  url      = each.value

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Failed to download dashboard ${each.key} from ${each.value}. Status: ${self.status_code}"
    }
  }
}

# Import community dashboards with remapped datasources
resource "grafana_dashboard" "imported" {
  for_each  = var.import_dashboards
  folder    = grafana_folder.imported.id
  overwrite = true

  # To ensure idempotency, prevent duplicates, and enforce non-editable status:
  # 1. Replace datasource variables in the raw JSON.
  # 2. Decode the JSON to inject a stable UID (based on the map key).
  # 3. Force the 'id' to null to avoid internal ID conflicts.
  # 4. Set 'editable' to false.
  config_json = jsonencode(
    merge(
      jsondecode(
        replace(
          replace(
            replace(
              replace(
                data.http.dashboard_json[each.key].response_body,
                "$${DS_PROMETHEUS}", local.dashboard_replacements["$${DS_PROMETHEUS}"]
              ),
              "$${datasource}", local.dashboard_replacements["$${datasource}"]
            ),
            "$${DS_OCI_METRICS}", local.dashboard_replacements["$${DS_OCI_METRICS}"]
          ),
          "$${DS_OCI_LOGS}", local.dashboard_replacements["$${DS_OCI_LOGS}"]
        )
      ),
      {
        uid      = each.key
        id       = null
        editable = false
      }
    )
  )

  # Ensure all potential datasources are ready before importing dashboards
  depends_on = [
    grafana_data_source.greptimedb,
    grafana_data_source.oci_metrics,
    grafana_data_source.oci_logs
  ]
}

# Grafana folder for custom dashboards
resource "grafana_folder" "custom" {
  count = length(var.custom_dashboards) > 0 ? 1 : 0
  title = var.custom_folder_name
}

# Provision custom dashboards with remapped datasources
resource "grafana_dashboard" "custom" {
  for_each  = var.custom_dashboards
  folder    = grafana_folder.custom[0].id
  overwrite = true

  config_json = jsonencode(
    merge(
      jsondecode(
        replace(
          replace(
            replace(
              replace(
                replace(
                  each.value,
                  "$${DS_PROMETHEUS}", local.dashboard_replacements["$${DS_PROMETHEUS}"]
                ),
                "$${datasource}", local.dashboard_replacements["$${datasource}"]
              ),
              "$${DS_LOGS}", local.dashboard_replacements["$${DS_LOGS}"]
            ),
            "$${DS_OCI_METRICS}", local.dashboard_replacements["$${DS_OCI_METRICS}"]
          ),
          "$${DS_OCI_LOGS}", local.dashboard_replacements["$${DS_OCI_LOGS}"]
        )
      ),
      {
        uid      = each.key
        id       = null
        editable = true
      }
    )
  )

  depends_on = [
    grafana_data_source.greptimedb,
    grafana_data_source.greptimedb_logs,
    grafana_data_source.oci_metrics,
    grafana_data_source.oci_logs
  ]
}

