# ================================================================================
# Networking
# Single-tier VNet: all VMSS instances live in one subnet. Azure Load Balancer
# does not occupy a subnet — it is fronted by a public IP only — so there is no
# need for a separate public subnet as there would be in AWS with an ALB.
# Instances reach the internet through a NAT gateway and are never directly
# reachable from outside the VNet.
#
# CIDR layout:
#   10.0.0.0/16   — VNet
#   10.0.1.0/24   — vmss-subnet (instances)
# ================================================================================

resource "azurerm_virtual_network" "main" {
  name                = "vmss-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = { Name = "vmss-vnet" }
}

# ================================================================================
# Instance Subnet
# VMSS instances are placed here. No public IPs are assigned — all inbound
# traffic arrives through the load balancer, and all outbound traffic exits
# through the NAT gateway. Instances are unreachable from the internet by design.
# ================================================================================

resource "azurerm_subnet" "vmss" {
  name                 = "vmss-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]

  # Disables Azure's default outbound access, which would otherwise assign
  # a public IP to every instance automatically — forces all outbound traffic
  # through the NAT gateway instead
  default_outbound_access_enabled = false

  # virtual_network_name resolves to a known string at plan time, so Terraform
  # does not infer a runtime dependency — explicit depends_on is required to
  # ensure the VNet exists before the subnet create request is made
  depends_on = [azurerm_virtual_network.main]
}

# ================================================================================
# Application Gateway Subnet
# Application Gateway v2 must occupy its own dedicated subnet — it cannot share
# with VMSS instances or any other resource type.
# ================================================================================

resource "azurerm_subnet" "appgw" {
  name                 = "appgw-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]

  depends_on = [azurerm_virtual_network.main]
}

# ================================================================================
# NAT Gateway
# Provides egress-only internet access for instances. Inbound connections from
# the internet cannot be initiated through a NAT gateway — instances can reach
# apt repos and Azure APIs but are not directly reachable from outside.
#
# A single NAT gateway covers all instances in this subnet. Production
# deployments may add a second gateway for redundancy across zones.
# ================================================================================

# Standard SKU is required — Basic NAT gateways cannot be associated with
# subnets that contain Standard LB backends
resource "azurerm_public_ip" "nat" {
  name                = "vmss-nat-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = { Name = "vmss-nat-pip" }
}

resource "azurerm_nat_gateway" "main" {
  name                = "vmss-nat"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard"

  tags = { Name = "vmss-nat" }
}

# Associates the static public IP with the NAT gateway as its egress address
resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Attaches the NAT gateway to the subnet — all outbound traffic from instances
# in this subnet will exit through the NAT gateway's public IP
resource "azurerm_subnet_nat_gateway_association" "vmss" {
  subnet_id      = azurerm_subnet.vmss.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}
