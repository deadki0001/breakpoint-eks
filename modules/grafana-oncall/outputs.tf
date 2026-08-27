output "alertmanager_webhook_url" {
  description = "URL to configure as Alertmanager's webhook receiver - this is what connects the EKS cluster's Alertmanager to Grafana Cloud OnCall"
  value       = grafana_oncall_integration.alertmanager.link
  sensitive   = true
}

output "escalation_chain_id" {
  value = grafana_oncall_escalation_chain.this.id
}
