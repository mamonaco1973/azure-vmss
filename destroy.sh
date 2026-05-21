#!/bin/bash
set -euo pipefail

terraform -chdir=01-vmss destroy -auto-approve
