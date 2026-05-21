#!/bin/bash
set -euo pipefail

# ================================================================================
# Environment Check
# Validates required tools are installed and Azure credentials are active
# ================================================================================

# ------------------------------------------------------------------------------
# Tool Checks
# ------------------------------------------------------------------------------

echo "NOTE: Validating that required commands are found in your PATH."

for cmd in az terraform; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is not found in PATH."
    exit 1
  fi
  echo "NOTE: $cmd is found in the current PATH."
done

echo "NOTE: All required commands are available."

# ------------------------------------------------------------------------------
# Azure Credentials
# az account show is the cheapest way to confirm az login has been run
# and the token has not expired
# ------------------------------------------------------------------------------

echo "NOTE: Checking Azure CLI connection."

if ! az account show &>/dev/null; then
  echo "ERROR: Azure credentials are not configured. Run 'az login' first."
  exit 1
fi

echo "NOTE: Successfully connected to Azure."
