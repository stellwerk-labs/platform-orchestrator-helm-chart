terraform {
  required_providers {
    platform-orchestrator = {
      source  = "stellwerk-labs/platform-orchestrator"
      version = "~> 1.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "platform-orchestrator" {}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "platform-orchestrator_environment_type" "development" {
  id           = "development"
  display_name = "Development Environment"
}

resource "platform-orchestrator_project" "test" {
  id           = var.project_id
  display_name = "Test Project"
}

resource "platform-orchestrator_environment" "test" {
  id           = var.environment_id
  project_id   = platform-orchestrator_project.test.id
  env_type_id  = platform-orchestrator_environment_type.development.id
  display_name = "Test Environment"
}
