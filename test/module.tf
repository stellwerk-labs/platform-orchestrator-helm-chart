resource "platform-orchestrator_resource_type" "test" {
  id          = var.resource_type_id
  description = "Test type"
  output_schema = jsonencode({
    type = "object"
    properties = {
      test_value = {
        description = "Test value"
        type        = "string"
      }
    }
  })
  is_developer_accessible = true
}

resource "platform-orchestrator_module" "test" {
  id            = var.module_id
  resource_type = platform-orchestrator_resource_type.test.id
  module_source = "inline"
  module_source_code = <<-EOT
    output "test_value" {
      value = "hello-world"
    }

    output "platform_orchestrator_metadata" {
      value = {
        Test-Value = "hello-metadata"
      }
    }
  EOT
}

resource "platform-orchestrator_module_rule" "test" {
  module_id = platform-orchestrator_module.test.id
}
