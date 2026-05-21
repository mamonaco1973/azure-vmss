output "appgw_fqdn" {
  description = "Application Gateway DNS name — open in browser to see the instance page"
  value       = azurerm_public_ip.appgw.fqdn
}

output "appgw_public_ip" {
  description = "Application Gateway public IP address"
  value       = azurerm_public_ip.appgw.ip_address
}
