# ##############################################################################
# ONCALL MODULE
#
# Manages Grafana Cloud OnCall resources via Terraform rather than clicking
# through the UI - an Alertmanager-type integration (which generates the
# webhook URL Alertmanager sends alerts to) and an escalation chain that
# actually notifies a person. This module talks to Grafana Cloud's API, not
# anything inside the EKS cluster - the cluster's Alertmanager just needs
# the webhook URL this module outputs, wired in separately via Alertmanager
# config.
# ##############################################################################

terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
  }
}

provider "grafana" {
  cloud_access_policy_token = var.grafana_cloud_api_token
  oncall_url                = var.grafana_oncall_url
}

resource "grafana_oncall_integration" "alertmanager" {
  name = "${var.project_name}-alertmanager"
  type = "alertmanager"

  default_route {
    escalation_chain_id = grafana_oncall_escalation_chain.this.id
  }
}

resource "grafana_oncall_escalation_chain" "this" {
  name = "${var.project_name}-escalation-chain"
}

data "grafana_oncall_user" "on_call_engineer" {
  username = var.grafana_oncall_username
}

resource "grafana_oncall_escalation" "notify_user" {
  escalation_chain_id = grafana_oncall_escalation_chain.this.id
  type                = "notify_persons"
  persons_to_notify    = [data.grafana_oncall_user.on_call_engineer.id]
  position             = 0
}
