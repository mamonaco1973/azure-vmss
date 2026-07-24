# ================================================================================
# SSH Key
# Generated at apply time — the private key is never written to disk or stored
# in state in plaintext. We only need the public key to satisfy Azure's admin
# SSH key requirement; SSH access is not used for this demo.
# ================================================================================

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# ================================================================================
# Virtual Machine Scale Set
# Maintains the desired number of Ubuntu instances spread across availability
# zones 1 and 2 in centralus. All instances register into the LB backend pool
# automatically — no manual target registration is required.
#
# Azure VMSS distributes instances across fault domains and zones automatically.
# Zone spreading here mirrors the AWS pattern of spanning two AZs.
# ================================================================================

resource "azurerm_linux_virtual_machine_scale_set" "main" {
  name                = "vmss-main"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Standard_B2pts_v2: 2 vCPU, 1 GiB RAM, Ampere Altra ARM, burstable.
  # Chosen to match the AWS t4g.micro (also 2 vCPU / 1 GiB ARM burstable) so
  # the cross-cloud comparison is not skewed by CPU architecture or core count.
  #
  # Azure has no 1-vCPU ARM size — every ARM series (Bpsv2, Dpsv5/v6,
  # Dplsv5/v6) starts at 2 vCPU, so the old Standard_B1s (1 vCPU x86) had no
  # direct ARM equivalent. Bpsv2 is the burstable ARM line; the Dpsv5 series
  # referenced previously is the general-purpose one and is not comparable.
  sku = "Standard_B2pts_v2"

  # Initial instance count — autoscale manages this after first apply.
  # ignore_changes prevents Terraform from overwriting autoscale's adjustments
  # on subsequent plans, which would cause constant drift.
  instances = 4

  admin_username = "azureuser"

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.ssh.public_key_openssh
  }

  # Ubuntu 24.04 LTS (Noble) — matches the AWS, GCP, and OCI builds so the
  # cross-cloud comparison is not skewed by distro differences. Note the 24.04
  # naming break: Canonical dropped the "0001-com-ubuntu-server-<codename>"
  # offer scheme used through 22.04 in favour of "ubuntu-24_04-lts".
  #
  # The SKU must be server-arm64, not server — "server" is x86-only and will
  # not boot on the Bpsv2 ARM size above.
  source_image_reference {
    publisher = "canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server-arm64"
    version   = "latest"
  }

  os_disk {
    # ReadWrite caching improves OS disk performance for read-heavy boot workloads
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  # base64encode mirrors filebase64() in AWS — keeps the script external without
  # needing a templatefile() wrapper
  custom_data = base64encode(file("${path.module}/scripts/custom_data.sh"))

  network_interface {
    name    = "vmss-nic"
    primary = true

    ip_configuration {
      name      = "vmss-ipconfig"
      primary   = true
      subnet_id = azurerm_subnet.vmss.id

      # Registering here causes Azure to add/remove instance NICs from the
      # App Gateway backend pool automatically as the scale set scales in and out
      application_gateway_backend_address_pool_ids = [
        tolist(azurerm_application_gateway.main.backend_address_pool)[0].id
      ]
    }
  }

  # Spread instances across zones 1 and 2 — analogous to spanning us-east-2a
  # and us-east-2b in AWS. If one zone has an outage the scale set keeps running.
  zones = ["1", "2"]

  # upgrade_mode Manual means existing instances are not replaced when the
  # VMSS model changes — new scale-out events pick up the latest model.
  upgrade_mode = "Manual"

  lifecycle {
    # Autoscale adjusts instance count at runtime — ignoring it here prevents
    # Terraform from fighting autoscale on every subsequent plan
    ignore_changes = [instances]
  }

  # Instances boot and run cloud-init immediately on creation. The NAT gateway
  # and NSG must be fully associated with the subnet before any instance starts,
  # otherwise apt-get has no outbound internet access and apache2 never installs.
  depends_on = [
    azurerm_subnet_nat_gateway_association.vmss,
    azurerm_subnet_network_security_group_association.vmss,
  ]

  tags = { Name = "vmss-instance" }
}

# ================================================================================
# Autoscale
# CPU-based rules mirror the AWS CloudWatch alarm pattern. The asymmetric
# evaluation windows (2 min scale-out, 10 min scale-in) react quickly to rising
# load but avoid removing instances too eagerly during brief CPU dips.
# ================================================================================

resource "azurerm_monitor_autoscale_setting" "main" {
  name                = "vmss-autoscale"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.main.id

  profile {
    name = "default"

    capacity {
      # Floor of 1 keeps the group alive at minimum cost during quiet periods;
      # ceiling of 6 caps spend during a runaway load event
      minimum = 1
      maximum = 6
      default = 4
    }

    # Scale out: add one instance after CPU exceeds 60% for 2 consecutive minutes
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT2M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 60
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = 1
        # 2-minute cooldown prevents a second scale-out before the first wave
        # of new instances has absorbed the load
        cooldown = "PT2M"
      }
    }

    # Scale in: remove one instance after CPU stays below 60% for 60 minutes —
    # long window prevents scale-in during demos and brief quiet periods
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT1H"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 60
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT2M"
      }
    }
  }
}
