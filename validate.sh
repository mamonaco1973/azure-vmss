#!/bin/bash
# ================================================================================
# File: validate.sh
# ================================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Step 1: Resolve App Gateway FQDN from Terraform output
# ------------------------------------------------------------------------------

LB_HOST=$(terraform -chdir=01-vmss output -raw appgw_fqdn 2>/dev/null || true)

if [ -z "${LB_HOST}" ]; then
  echo "ERROR: Could not read Terraform outputs. Run ./apply.sh first."
  exit 1
fi

echo "NOTE: App Gateway endpoint: http://${LB_HOST}"

# ------------------------------------------------------------------------------
# Step 2: Wait for HTTP response from the Application Gateway
# Polls every 10s — instances need time for cloud-init to run and start apache2
# ------------------------------------------------------------------------------

echo "NOTE: Waiting for HTTP response from Application Gateway..."

TIMEOUT=300
ELAPSED=0

while true; do
  if curl -sf --max-time 5 "http://${LB_HOST}/plain" &>/dev/null; then
    echo "NOTE: Application Gateway is responding."
    break
  fi

  if [ "${ELAPSED}" -ge "${TIMEOUT}" ]; then
    echo "ERROR: Timed out waiting for HTTP response after ${TIMEOUT}s."
    exit 1
  fi

  echo "NOTE: No response yet — retrying in 10s (${ELAPSED}s elapsed)..."
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

# ------------------------------------------------------------------------------
# Step 3: Sample responses
# Hit the endpoint 6 times — different IPs confirm load balancing is working
# ------------------------------------------------------------------------------

echo "NOTE: Sampling App Gateway responses..."
echo ""

for i in $(seq 1 10); do
  RESPONSE=$(curl -sf "http://${LB_HOST}/plain")
  echo "  [${i}] ${RESPONSE}"
done

echo ""
echo "================================================================================="
echo "  VM Scale Set — Deployment validated!"
echo "================================================================================="
echo "  LB : http://${LB_HOST}"
echo "================================================================================="
