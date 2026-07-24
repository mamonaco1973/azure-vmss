#!/bin/bash
# ================================================================================
# File: validate.sh
# ================================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Deploy Timing
# T_ANCHOR is the start of the whole deployment. apply.sh exports DEPLOY_START
# so the headline number spans terraform apply + provisioning + boot + health
# checks — the same window on every cloud, which is what makes cross-provider
# comparison valid.
#
# Running validate.sh standalone falls back to "now", which is NOT comparable
# across providers: Azure's VMSS apply blocks until instances are provisioned,
# so most of the wait has already happened by the time validate.sh starts.
#
# Poll interval is fixed at 5s in all four projects — measurement resolution
# cannot be finer than the poll.
# ------------------------------------------------------------------------------

T_ANCHOR="${DEPLOY_START:-$(date +%s)}"
T_VALIDATE_START=$(date +%s)
POLL=5

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

TIMEOUT=900

while true; do
  HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 \
    "http://${LB_HOST}/plain" 2>/dev/null || echo "000")

  if [ "${HTTP_CODE}" = "200" ]; then
    T_FIRST_OK=$(date +%s)
    echo "NOTE: Application Gateway is responding."
    break
  fi

  # Elapsed is read from the clock, not accumulated from sleeps — curl can
  # burn up to --max-time before returning, so a sleep counter drifts
  ELAPSED=$(( $(date +%s) - T_VALIDATE_START ))
  if [ "${ELAPSED}" -ge "${TIMEOUT}" ]; then
    echo "ERROR: Timed out waiting for HTTP 200 after ${TIMEOUT}s."
    exit 1
  fi

  echo "NOTE: HTTP ${HTTP_CODE} — retrying in ${POLL}s (${ELAPSED}s elapsed)..."
  sleep "${POLL}"
done

# ------------------------------------------------------------------------------
# Step 3: Sample responses
# Hit the endpoint 6 times — different IPs confirm load balancing is working
# ------------------------------------------------------------------------------

echo "NOTE: Sampling App Gateway responses..."
echo ""

# The wait loop above breaks on the FIRST 200, so only one instance is
# guaranteed healthy here — the gateway will still route some samples to
# instances that are mid-boot. A bare `curl -sf` returns non-zero on those,
# and under `set -e` that aborts the script before the timing summary below
# ever prints. Sampling is diagnostic, so a failed sample must not be fatal.
for i in $(seq 1 10); do
  RESPONSE=$(curl -sf --max-time 5 "http://${LB_HOST}/plain" || echo "(no response yet)")
  echo "  [${i}] ${RESPONSE}"
done

echo ""
echo "================================================================================="
echo "  VM Scale Set — Deployment validated!"
echo "================================================================================="
echo "  LB : http://${LB_HOST}"
echo "---------------------------------------------------------------------------------"
echo "  Time to first request : $((T_FIRST_OK - T_ANCHOR))s"
if [ -z "${DEPLOY_START:-}" ]; then
  echo "  WARNING: DEPLOY_START unset — timed from validate.sh only, which is"
  echo "           NOT comparable across clouds. Run ./apply.sh for the real number."
else
  echo "  Health wait only      : $((T_FIRST_OK - T_VALIDATE_START))s"
fi
echo "================================================================================="
