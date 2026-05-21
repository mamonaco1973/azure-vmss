#!/bin/bash
set -euo pipefail

./check_env.sh

terraform -chdir=01-vmss init
terraform -chdir=01-vmss apply -auto-approve

./validate.sh
