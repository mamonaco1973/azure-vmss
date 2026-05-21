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
