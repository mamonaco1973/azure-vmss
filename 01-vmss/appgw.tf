# ================================================================================
# Application Gateway
# Layer 7 load balancer — the Azure equivalent of AWS ALB. Routes each HTTP
# request independently, giving even distribution across instances regardless
# of persistent TCP connections. Requires its own dedicated subnet.
# ================================================================================

# Standard SKU with zones matches the App Gateway requirement — Basic SKU does
# not support zone redundancy or Application Gateway v2
resource "azurerm_public_ip" "appgw" {
  name                = "vmss-appgw-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2"]

  # Unique DNS label scoped to centralus — gives a stable hostname without
  # needing a custom domain. Random suffix avoids collisions if the template
  # is deployed more than once in the same region.
  domain_name_label = "vmss-appgw-${random_integer.dns_suffix.result}"

  tags = { Name = "vmss-appgw-pip" }
}

resource "azurerm_application_gateway" "main" {
  name                = "vmss-appgw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Zone redundancy — distributes gateway capacity across two AZs so a single
  # zone failure does not take the entry point offline
  zones = ["1", "2"]

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"

    # capacity = 1 is the minimum for a fixed-capacity gateway. Autoscaling
    # the gateway itself is also possible but unnecessary for this demo.
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "vmss-appgw-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_ip_configuration {
    name                 = "vmss-appgw-frontend"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = "http-port"
    port = 80
  }

  # The backend pool is populated automatically by the VMSS — instances
  # register and deregister here as the scale set scales in and out
  backend_address_pool {
    name = "vmss-backend-pool"
  }

  backend_http_settings {
    name                  = "http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = "http-probe"

    # Use the backend instance's IP as the HTTP Host header — avoids needing
    # a custom domain name for the health probe to succeed
    pick_host_name_from_backend_address = true
  }

  # HTTP health probe on / — a 200 response means apache2 is up and serving
  probe {
    name                                      = "http-probe"
    protocol                                  = "Http"
    path                                      = "/"
    interval                                  = 10
    timeout                                   = 10
    unhealthy_threshold                       = 2

    # Inherit host header from backend HTTP settings rather than hard-coding
    # an IP, so the probe works regardless of instance IP assignment
    pick_host_name_from_backend_http_settings = true
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "vmss-appgw-frontend"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "http-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "vmss-backend-pool"
    backend_http_settings_name = "http-settings"
    priority                   = 1
  }
}
