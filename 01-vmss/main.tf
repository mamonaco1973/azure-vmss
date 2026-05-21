# ================================================================================
# Provider Configuration
# Pins azurerm to 4.x — minor upgrades are allowed but 5.x breaking changes are
# blocked. The tls provider generates an SSH key pair at apply time so the VMSS
# has a valid admin key without storing secrets in the repository.
# ================================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  # Reads subscription from ARM_SUBSCRIPTION_ID env var set by az login.
  # The resource_group block prevents Terraform from erroring on destroy when
  # the group still contains resources being removed in the same plan.
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# ================================================================================
# Resource Group
# All resources share a single group — destroying the group is a single operation
# that removes every resource created by this module with no ordering concerns.
# ================================================================================

resource "azurerm_resource_group" "main" {
  name = "vmss-rg"

  location = "centralus"
}

# Generates a unique numeric suffix for the Application Gateway DNS label —
# avoids collisions if the template is deployed multiple times in the same region
resource "random_integer" "dns_suffix" {
  min = 10000
  max = 99999
}
