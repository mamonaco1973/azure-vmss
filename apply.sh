#!/bin/bash
set -euo pipefail

terraform -chdir=01-autoscaling init
terraform -chdir=01-autoscaling apply -auto-approve

./validate.sh
