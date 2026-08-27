variable "project_name" {
  description = "Short name used to prefix OnCall resource names"
  type        = string
}

variable "grafana_cloud_api_token" {
  description = "Grafana Cloud access policy token with alerts/rules read+write scope"
  type        = string
  sensitive   = true
}

variable "grafana_oncall_url" {
  description = "Grafana Cloud OnCall API base URL - specific to your stack's region, found in the OnCall integration webhook URL (e.g. https://<region>.grafana.net/oncall)"
  type        = string
}

variable "grafana_oncall_username" {
  description = "Grafana Cloud username to notify in the escalation chain (e.g. 'adkinsdevon', from your profile page)"
  type        = string
}
