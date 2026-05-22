# CLAUDE.md — azure-vmss

## What This Project Does

Deploys a minimal Azure VM Scale Set of Apache web servers behind an
Application Gateway. Each instance displays its own metadata (private IP,
VM name, zone, VM size) fetched from Azure IMDS on a styled page.
Instances are private (no public IP); outbound access via NAT Gateway.

## Commands

```bash
./apply.sh      # check env, terraform init + apply, then validate
./destroy.sh    # teardown all resources
./validate.sh   # poll App Gateway FQDN, sample 10 /plain responses
```

## Architecture

Single Terraform phase in `01-vmss/`. No modules, no workspaces.

- **Region:** centralus
- **Instance:** Standard_B1s (1 vCPU, 1 GiB) — cheapest burstable in Azure
- **LB:** Application Gateway Standard_v2 (L7) — per-request routing
- **VMSS:** min 1, desired 4, max 6 across zones 1 and 2
- **Scaling:** Azure Monitor autoscale, CPU-based
- **Startup:** `scripts/custom_data.sh` — processed by cloud-init via `custom_data`

## Scaling Policy

Scale-out triggers after CPU > 60% for a 2-minute window.
Scale-in triggers after CPU < 60% for a 1-hour window.

| Rule      | Condition  | Window | Action      |
|-----------|------------|--------|-------------|
| scale-out | CPU > 60%  | 2 min  | +1 instance |
| scale-in  | CPU < 60%  | 1 hour | -1 instance |

## Critical Terraform Gotchas

These three patterns are non-obvious and caused deployment failures:

1. **Subnet `depends_on` required.** `virtual_network_name` resolves to a
   known string at plan time, so Terraform creates no runtime dependency on
   the VNet. Both subnets must have `depends_on = [azurerm_virtual_network.main]`
   or subnet creation races the VNet and fails with a 404.

2. **`default_outbound_access_enabled = false` on vmss-subnet.** Without
   this, Azure silently assigns a shared public IP to every instance NIC.
   Instances should be fully private with NAT Gateway for egress only.

3. **VMSS depends on NAT GW and NSG subnet associations.** VMSS instances
   boot and run cloud-init immediately on creation. If the NAT gateway
   association isn't complete first, apt-get has no internet and apache2
   never installs. The VMSS resource must declare:
   ```hcl
   depends_on = [
     azurerm_subnet_nat_gateway_association.vmss,
     azurerm_subnet_network_security_group_association.vmss,
   ]
   ```

## Other Notable Patterns

- **App Gateway dedicated subnet:** Azure requires the App Gateway to have
  its own subnet (`appgw-subnet`). It cannot share with the VMSS subnet.
- **App Gateway NSG:** Must allow GatewayManager ports 65200–65535 inbound
  or the gateway will fail to provision.
- **DNS label:** Public IP uses `domain_name_label` with a `random_integer`
  suffix (10000–99999) — avoids name collisions across deployments.
- **`lifecycle { ignore_changes = [instances] }`** on the VMSS prevents
  Terraform from overwriting autoscale's instance count adjustments.
- **Azure IMDS:** No session token required — only `Metadata: true` header.
  Response is JSON; `jq` is needed to parse it.
- **Azure portal public IP display:** The portal shows the NAT Gateway's
  shared egress IP on the instance overview. Instances have no dedicated
  public IP — this display is cosmetically misleading.

## Key Files

| File | Purpose |
|------|---------|
| `01-vmss/vmss.tf` | VMSS resource and Azure Monitor autoscale setting |
| `01-vmss/appgw.tf` | Application Gateway, public IP, health probe |
| `01-vmss/networking.tf` | VNet, subnets, NAT Gateway, associations |
| `01-vmss/security.tf` | NSGs for vmss-subnet and appgw-subnet |
| `01-vmss/scripts/custom_data.sh` | cloud-init: installs Apache + jq, fetches IMDS, writes HTML + /plain |
