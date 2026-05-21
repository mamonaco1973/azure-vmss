#!/bin/bash
# ================================================================================
# File: validate.sh
# ================================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Step 1: Resolve LB public IP from Terraform output
# ------------------------------------------------------------------------------

LB_IP=$(terraform -chdir=01-vmss output -raw lb_public_ip 2>/dev/null || true)

if [ -z "${LB_IP}" ]; then
  echo "ERROR: Could not read Terraform outputs. Run ./apply.sh first."
  exit 1
fi

echo "NOTE: LB endpoint: http://${LB_IP}"

# ------------------------------------------------------------------------------
# Step 2: Wait for HTTP response from the load balancer
# Polls every 10s — instances need time for cloud-init to run and start apache2
# ------------------------------------------------------------------------------

echo "NOTE: Waiting for HTTP response from load balancer..."

TIMEOUT=300
ELAPSED=0

while true; do
  if curl -sf --max-time 5 "http://${LB_IP}/plain" &>/dev/null; then
    echo "NOTE: Load balancer is responding."
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
# Step 3: Sample LB responses
# Hit the endpoint 6 times — different IPs confirm load balancing is working
# ------------------------------------------------------------------------------

echo "NOTE: Sampling LB responses..."
echo ""

for i in $(seq 1 6); do
  RESPONSE=$(curl -sf "http://${LB_IP}/plain")
  echo "  [${i}] ${RESPONSE}"
done

echo ""
echo "================================================================================="
echo "  VM Scale Set — Deployment validated!"
echo "================================================================================="
echo "  LB : http://${LB_IP}"
echo "================================================================================="
