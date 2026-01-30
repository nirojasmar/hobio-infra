output "rabbitmq_instance_name" {
  description = "The name of the RabbitMQ instance"
  value       = google_compute_instance.rabbitmq_instance.name
}

output "rabbitmq_internal_ip" {
  description = "The internal IP of the RabbitMQ instance"
  value       = google_compute_instance.rabbitmq_instance.network_interface[0].network_ip
}

output "rabbitmq_connection_string" {
  value       = "amqp://admin:SecretPass123@${google_compute_instance.rabbitmq_instance.network_interface[0].network_ip}:5672"
  sensitive   = true
}

output "ssh_command_iap" {
  description = "Command to connect to the RabbitMQ instance using IAP"
  value       = "gcloud compute ssh ${google_compute_instance.rabbitmq_instance.name} --tunnel-through-iap --project=${var.project_id} --zone=${google_compute_instance.rabbitmq_instance.zone}"
}