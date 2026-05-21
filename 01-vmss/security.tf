# ================================================================================
# Network Security Group
# Controls inbound traffic to VMSS instances. Only port 80 is open — instances
# are not directly SSH-accessible from the internet. The Azure platform's default
# deny-all-inbound rule blocks everything else without needing explicit deny rules.
#
# Unlike AWS where security groups are stateful and attached per-NIC, Azure NSGs
# are associated with subnets and apply to all resources placed in that subnet.
# ================================================================================

resource "azurerm_network_security_group" "vmss" {
  name                = "vmss-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Allow HTTP from any source — covers both client traffic forwarded by the
  # load balancer and health probe traffic from the Azure platform (168.63.129.16)
  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = { Name = "vmss-nsg" }
}

# Associates the NSG with the VMSS subnet — all instances in the subnet
# inherit these rules without needing per-NIC NSG attachments
resource "azurerm_subnet_network_security_group_association" "vmss" {
  subnet_id                 = azurerm_subnet.vmss.id
  network_security_group_id = azurerm_network_security_group.vmss.id
}

# ================================================================================
# Application Gateway NSG
# App Gateway v2 requires ports 65200-65535 open inbound from GatewayManager —
# this is Azure's infrastructure channel for health and management traffic.
# Without it, the gateway will fail to provision.
# ================================================================================

resource "azurerm_network_security_group" "appgw" {
  name                = "appgw-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Required by App Gateway v2 — Azure's control plane communicates with the
  # gateway over this port range and will reject the deployment without it
  security_rule {
    name                       = "allow-gateway-manager"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  # Allows client HTTP traffic to reach the Application Gateway frontend
  security_rule {
    name                       = "allow-http"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = { Name = "appgw-nsg" }
}

resource "azurerm_subnet_network_security_group_association" "appgw" {
  subnet_id                 = azurerm_subnet.appgw.id
  network_security_group_id = azurerm_network_security_group.appgw.id
}
