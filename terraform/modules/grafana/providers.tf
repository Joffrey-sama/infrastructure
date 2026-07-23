terraform {
  required_version = ">= 1.0"
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

# Grafana provider configuration
# Uses grafana_url and grafana_api_token from terraform.tfvars
provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_api_token
}
