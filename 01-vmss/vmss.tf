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
# zones 1 and 2 in eastus2. All instances register into the LB backend pool
# automatically — no manual target registration is required.
#
# Azure VMSS distributes instances across fault domains and zones automatically.
# Zone spreading here mirrors the AWS pattern of spanning two AZs.
# ================================================================================

resource "azurerm_linux_virtual_machine_scale_set" "main" {
  name                = "vmss-main"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Standard_B1s: 1 vCPU, 1 GiB RAM — ARM equivalent of t4g.micro in AWS.
  # Burstable compute is well-suited for this demo workload.
  sku = "Standard_B1s"

  # Initial instance count — autoscale manages this after first apply.
  # ignore_changes prevents Terraform from overwriting autoscale's adjustments
  # on subsequent plans, which would cause constant drift.
  instances = 4

  admin_username = "azureuser"

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.ssh.public_key_openssh
  }

  # Ubuntu 22.04 LTS (Jammy) — widely supported, long-term support until 2027.
  # apache2 and jq are available in the default apt repositories.
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    # ReadWrite caching improves OS disk performance for read-heavy boot workloads
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # base64encode mirrors filebase64() in AWS — keeps the script external without
  # needing a templatefile() wrapper
  custom_data = base64encode(file("${path.module}/scripts/userdata.sh"))

  network_interface {
    name    = "vmss-nic"
    primary = true

    ip_configuration {
      name      = "vmss-ipconfig"
      primary   = true
      subnet_id = azurerm_subnet.vmss.id

      # Registering here causes Azure to add/remove instance NICs from the
      # pool automatically as the scale set scales in and out
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.main.id]
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

    # Scale in: remove one instance after CPU stays below 60% for 10 minutes
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 60
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = 1
        # 2-minute cooldown after scale-in matches scale-out cooldown —
        # prevents immediate re-scaling if load briefly spikes post-removal
        cooldown = "PT2M"
      }
    }
  }
}
