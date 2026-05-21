#!/bin/bash
set -euo pipefail

# ================================================================================
# Environment Check
# Validates required tools are installed and AWS credentials are active
# ================================================================================

# ------------------------------------------------------------------------------
# Tool Checks
# ------------------------------------------------------------------------------

echo "NOTE: Validating that required commands are found in your PATH."

for cmd in aws terraform; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is not found in PATH."
    exit 1
  fi
  echo "NOTE: $cmd is found in the current PATH."
done

echo "NOTE: All required commands are available."

# ------------------------------------------------------------------------------
# AWS Credentials
# sts get-caller-identity is the cheapest way to confirm credentials are active
# ------------------------------------------------------------------------------

echo "NOTE: Checking AWS CLI connection."

if ! aws sts get-caller-identity &>/dev/null; then
  echo "ERROR: AWS credentials are not configured or have expired."
  exit 1
fi

echo "NOTE: Successfully connected to AWS."
