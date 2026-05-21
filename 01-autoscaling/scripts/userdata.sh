#!/bin/bash
# ================================================================================
# userdata.sh
# Runs once on first boot via cloud-init. Installs Apache, fetches instance
# metadata via IMDSv2, and writes an AWS-themed HTML page to the web root.
# ================================================================================

yum install -y httpd

# ------------------------------------------------------------------------------
# Fetch Instance Metadata
# IMDSv2 requires a session token — IMDSv1 is disabled on AL2023 by default
# ------------------------------------------------------------------------------

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-type)

# ------------------------------------------------------------------------------
# Write HTML Page
# ------------------------------------------------------------------------------

cat > /var/www/html/index.html <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>AWS Auto Scaling</title>
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
      border-top: 3px solid #FF9900;
      padding: 48px 52px;
      width: 480px;
      box-shadow: 0 12px 40px rgba(0,0,0,0.5);
    }
    .badge-row {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 28px;
    }
    .aws-badge {
      background: #FF9900;
      color: #232F3E;
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
      color: #FF9900;
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
      <span class="aws-badge">AWS</span>
      <span class="badge-label">EC2 Auto Scaling</span>
    </div>
    <div class="title">&#x2601; Instance Details</div>
    <table>
      <tr>
        <td class="label">Private IP</td>
        <td class="value">$IP</td>
      </tr>
      <tr>
        <td class="label">Instance ID</td>
        <td class="value">$INSTANCE_ID</td>
      </tr>
      <tr>
        <td class="label">Availability Zone</td>
        <td class="value">$AZ</td>
      </tr>
      <tr>
        <td class="label">Instance Type</td>
        <td class="value">$INSTANCE_TYPE</td>
      </tr>
    </table>
    <div class="footer">Amazon Web Services &bull; Auto Scaling Group</div>
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

systemctl enable httpd
systemctl start httpd
