#!/bin/bash
# ================================================================================
# userdata.sh
# Runs once on first boot via cloud-init. Installs Apache, fetches instance
# metadata via Azure IMDS, and writes an Azure-themed HTML page to the web root.
# ================================================================================

apt-get update -y
# jq is needed to parse the Azure IMDS JSON response
apt-get install -y apache2 jq

# ------------------------------------------------------------------------------
# Fetch Instance Metadata
# Azure IMDS requires the Metadata: true header but no session token, unlike
# AWS IMDSv2. The response is JSON — jq extracts the fields we need.
# ------------------------------------------------------------------------------

METADATA=$(curl -sf -H "Metadata: true" \
  "http://169.254.169.254/metadata/instance?api-version=2021-02-01")

IP=$(echo "$METADATA" | jq -r \
  '.network.interface[0].ipv4.ipAddress[0].privateIpAddress')

VM_NAME=$(echo "$METADATA" | jq -r '.compute.name')

# Zone is empty when the VMSS is not zone-pinned; fall back to location so
# the HTML field always has a meaningful value
ZONE=$(echo "$METADATA" | jq -r '.compute.zone')
if [ -z "$ZONE" ] || [ "$ZONE" = "null" ]; then
  ZONE=$(echo "$METADATA" | jq -r '.compute.location')
fi

VM_SIZE=$(echo "$METADATA" | jq -r '.compute.vmSize')

# ------------------------------------------------------------------------------
# Write HTML Page
# ------------------------------------------------------------------------------

cat > /var/www/html/index.html <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Azure VM Scale Set</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #FFFFFF;
      font-family: -apple-system, 'Segoe UI', Arial, sans-serif;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .card {
      background: #1A2535;
      border-radius: 6px;
      border-top: 3px solid #0078D4;
      padding: 48px 52px;
      width: 480px;
      box-shadow: 0 12px 40px rgba(0,0,0,0.15);
    }
    .badge-row {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 28px;
    }
    .azure-badge {
      background: #0078D4;
      color: #FFFFFF;
      font-size: 11px;
      font-weight: 800;
      padding: 3px 8px;
      border-radius: 2px;
      letter-spacing: 1px;
    }
    .badge-label {
      color: #6B7A90;
      font-size: 12px;
      letter-spacing: 1.5px;
      text-transform: uppercase;
    }
    .title {
      color: #FFFFFF;
      font-size: 20px;
      font-weight: 300;
      margin-bottom: 36px;
    }
    table { width: 100%; border-collapse: collapse; }
    tr { border-bottom: 1px solid #263040; }
    tr:last-child { border-bottom: none; }
    td { padding: 14px 0; }
    .label {
      color: #6B7A90;
      font-size: 11px;
      letter-spacing: 1.2px;
      text-transform: uppercase;
      width: 50%;
    }
    .value {
      color: #0078D4;
      font-family: 'Courier New', Courier, monospace;
      font-size: 14px;
      font-weight: 600;
      text-align: right;
    }
    .footer {
      margin-top: 32px;
      padding-top: 20px;
      border-top: 1px solid #263040;
      text-align: center;
      color: #3A4A5A;
      font-size: 10px;
      letter-spacing: 2px;
      text-transform: uppercase;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge-row">
      <span class="azure-badge">AZURE</span>
      <span class="badge-label">VM Scale Set</span>
    </div>
    <div class="title">&#x2601; Instance Details</div>
    <table>
      <tr>
        <td class="label">Private IP</td>
        <td class="value">$IP</td>
      </tr>
      <tr>
        <td class="label">VM Name</td>
        <td class="value">$VM_NAME</td>
      </tr>
      <tr>
        <td class="label">Zone</td>
        <td class="value">$ZONE</td>
      </tr>
      <tr>
        <td class="label">VM Size</td>
        <td class="value">$VM_SIZE</td>
      </tr>
    </table>
    <div class="footer">Microsoft Azure &bull; VM Scale Set</div>
  </div>
</body>
</html>
HTMLEOF

# Plain-text endpoint for scripted health checks — avoids piping HTML through
# validate.sh and polluting terminal output
echo "$IP" > /var/www/html/plain

# ------------------------------------------------------------------------------
# Start Apache
# enable persists the service across reboots; start brings it up immediately
# ------------------------------------------------------------------------------

systemctl enable apache2
systemctl start apache2
