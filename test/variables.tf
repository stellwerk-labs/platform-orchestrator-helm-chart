variable "cluster_name" {
  description = "Name of the test cluster"
  type        = string
  default     = "test-orch"
}

variable "runner_namespace" {
  description = "Kubernetes namespace for the runner"
  type        = string
  default     = "platform-orchestrator-runner"
}

variable "runner_service_account" {
  description = "Kubernetes service account name for the runner"
  type        = string
  default     = "platform-orchestrator-runner"
}

variable "project_id" {
  description = "Platform Orchestrator project ID"
  type        = string
  default     = "test-project"
}

variable "environment_id" {
  description = "Platform Orchestrator environment ID"
  type        = string
  default     = "test-environment"
}

variable "module_id" {
  description = "Platform Orchestrator module ID"
  type        = string
  default     = "test-module"
}

variable "resource_type_id" {
  description = "Platform Orchestrator resource type ID"
  type        = string
  default     = "test-type"
}

variable "cluster_server" {
  description = "Kubernetes API server URL"
  type        = string
  default     = "https://kubernetes.default.svc"
}
