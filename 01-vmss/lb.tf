# ================================================================================
# Load Balancer
# The Standard public load balancer is the single internet-facing entry point.
# Unlike AWS ALB which occupies subnets, an Azure LB frontend is simply a public
# IP — no subnet reservation is required. The backend pool holds references to
# VMSS instances, which the scale set manages automatically as it scales in/out.
# ================================================================================

# Standard SKU is required when the backend instances use a Standard-SKU NAT
# gateway — mixing Basic and Standard SKUs on the same subnet is not allowed
resource "azurerm_public_ip" "lb" {
  name                = "vmss-lb-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = { Name = "vmss-lb-pip" }
}

resource "azurerm_lb" "main" {
  name                = "vmss-lb"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Standard SKU enables zone-redundant frontends and is required for VMSS
  # backends that span availability zones
  sku = "Standard"

  frontend_ip_configuration {
    name                 = "vmss-lb-frontend"
    public_ip_address_id = azurerm_public_ip.lb.id
  }

  tags = { Name = "vmss-lb" }
}

# The backend pool is the logical container that VMSS NICs register into.
# Instances are added and removed here automatically as the scale set changes.
resource "azurerm_lb_backend_address_pool" "main" {
  name            = "vmss-backend-pool"
  loadbalancer_id = azurerm_lb.main.id
}

# HTTP probe on / — a 200 from Apache means the instance is ready to serve
# traffic. Unhealthy instances are removed from the backend pool automatically.
resource "azurerm_lb_probe" "http" {
  name            = "vmss-http-probe"
  loadbalancer_id = azurerm_lb.main.id
  protocol        = "Http"
  port            = 80
  request_path    = "/"

  # Check every 10 seconds — fast enough to detect a failed instance within
  # a minute without generating excessive probe traffic
  interval_in_seconds = 10

  # Two consecutive failures pull the instance from rotation; two successes
  # add it back — asymmetric thresholds keep flapping instances out longer
  number_of_probes = 2
}

# Forwards all port-80 traffic from the frontend IP to the backend pool.
# Session persistence is None — each new TCP connection may land on any
# healthy instance, which demonstrates load distribution in validate.sh.
resource "azurerm_lb_rule" "http" {
  name                           = "vmss-http-rule"
  loadbalancer_id                = azurerm_lb.main.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "vmss-lb-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main.id]
  probe_id                       = azurerm_lb_probe.http.id
}
