#!/bin/bash
set -euo pipefail

terraform -chdir=01-autoscaling destroy -auto-approve
