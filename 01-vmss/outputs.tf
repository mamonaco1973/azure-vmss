output "lb_public_ip" {
  description = "Load balancer public IP — open in browser to see the instance page"
  value       = azurerm_public_ip.lb.ip_address
}
