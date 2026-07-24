#!/bin/bash
set -euo pipefail

./check_env.sh

terraform -chdir=01-vmss init

# Anchor for the deploy-timing metric reported by validate.sh. Set after init
# so provider download time (a local cache concern) is excluded.
export DEPLOY_START=$(date +%s)

terraform -chdir=01-vmss apply -auto-approve

./validate.sh
