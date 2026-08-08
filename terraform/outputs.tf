output "web_public_ip" {
  description = "Public IP of the web server - use this to access the app"
  value       = aws_instance.web.public_ip
}

output "web_private_ip" {
  value = aws_instance.web.private_ip
}

output "db_private_ip" {
  description = "Private IP of the database server - only reachable through the web server"
  value       = aws_instance.db.private_ip
}

# Auto-generate an Ansible inventory file as soon as `terraform apply` finishes
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content  = <<-EOT
  [web]
  ${aws_instance.web.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/${var.key_name}.pem

  [db]
  ${aws_instance.db.private_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/${var.key_name}.pem ansible_ssh_common_args='-o ProxyCommand="ssh -W %h:%p -q ubuntu@${aws_instance.web.public_ip} -i ~/.ssh/${var.key_name}.pem"'

  [all:vars]
  ansible_python_interpreter=/usr/bin/python3
  EOT
}
