provider "null" {}

variable "server_name" {
  type = string
}

variable "environment" {
  type    = string
  default = "dev"
}

resource "null_resource" "server_info" {
  provisioner "local-exec" {
    command = "echo \"Server: ${var.server_name}, Env: ${var.environment}\" > /tmp/ageval/infra/server_info.txt"
  }
}

output "server_info_path" {
  value = "/tmp/ageval/infra/server_info.txt"
}
