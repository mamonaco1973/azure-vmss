# Azure VM Scale Set

This project demonstrates a minimal Azure VM Scale Set (VMSS) deployment using Terraform. It provisions a fleet of Apache web servers behind an Azure Application Gateway, with each instance displaying its own metadata — private IP, VM name, availability zone, and VM size — on a styled page.

Instances run on Standard_B1s Ubuntu VMs and are never directly reachable from the internet. All inbound traffic flows through the Application Gateway. A NAT Gateway provides outbound internet access for package installation. Azure Monitor autoscale rules drive automatic scale-out and scale-in between 1 and 6 instances based on CPU utilization.

This solution is ideal for understanding the fundamentals of Azure VM Scale Sets without the complexity of application-specific configuration. It uses no Packer, no custom image, and deploys in a single Terraform phase.

## Prerequisites

* [An Azure Account](https://portal.azure.com/)
* [Install Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
* [Install Latest Terraform](https://developer.hashicorp.com/terraform/install)

If this is your first time watching our content, we recommend starting with this video: [Azure + Terraform: Easy Setup](https://youtu.be/BCMQo0CB9wk). It provides a step-by-step guide to properly configure Terraform and the Azure CLI.

---

## Download this Repository

```bash
git clone https://github.com/mamonaco1973/azure-vmss.git
cd azure-vmss
```

---

## Authenticate to Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

---

## Build the Code

Run [check_env](check_env.sh) to validate your environment, then run [apply](apply.sh) to provision the infrastructure.

```bash
./apply.sh
```

[apply.sh](apply.sh) runs `terraform init` and `terraform apply`, then automatically calls [validate.sh](validate.sh) to confirm the deployment is healthy. Note that the Application Gateway takes 5-8 minutes to provision.

---

### Build Results

When the deployment completes, the following resources are created:

- **Networking:**
  - A VNet (10.0.0.0/16) in centralus with two subnets:
    - `vmss-subnet` (10.0.1.0/24) — VMSS instances
    - `appgw-subnet` (10.0.2.0/24) — Application Gateway (dedicated, required by Azure)
  - NAT Gateway with a static public IP for instance outbound access

- **Security:**
  - NSG on the VMSS subnet: allows inbound port 80
  - NSG on the App Gateway subnet: allows port 80 and gateway manager ports 65200-65535

- **Application Gateway:**
  - Standard_v2, zone-redundant (zones 1 and 2)
  - Static public IP with a unique DNS label (`vmss-appgw-<random>.centralus.cloudapp.azure.com`)
  - HTTP health probe on `/` with 10-second intervals
  - Layer 7 per-request load balancing — even distribution across instances

- **VM Scale Set:**
  - Ubuntu 22.04 LTS, Standard_B1s, spread across availability zones 1 and 2
  - min 1, desired 4, max 6 instances
  - Apache installed via cloud-init; displays Azure IMDS metadata page
  - Azure Monitor autoscale driving scale-out and scale-in on CPU

---

### Scaling Policies

| Rule      | Condition  | Window  | Action      |
|-----------|------------|---------|-------------|
| scale-out | CPU > 60%  | 2 min   | +1 instance |
| scale-in  | CPU < 60%  | 1 hour  | -1 instance |

The long scale-in window (1 hour) prevents instances from being removed during demos or brief quiet periods.

---

### Validate the Deployment

[validate.sh](validate.sh) is called automatically by [apply.sh](apply.sh). It polls the Application Gateway until it responds, then samples 6 responses to confirm load balancing is working. Because the Application Gateway is Layer 7, each request is routed independently — different IP addresses across requests confirm even distribution.

```
NOTE: App Gateway endpoint: http://vmss-appgw-12345.centralus.cloudapp.azure.com
NOTE: Waiting for HTTP response from Application Gateway...
NOTE: Application Gateway is responding.
NOTE: Sampling App Gateway responses...

  [1] 10.0.1.4
  [2] 10.0.1.6
  [3] 10.0.1.5
  [4] 10.0.1.7
  [5] 10.0.1.4
  [6] 10.0.1.6

=================================================================================
  VM Scale Set — Deployment validated!
=================================================================================
  LB : http://vmss-appgw-12345.centralus.cloudapp.azure.com
=================================================================================
```

---

### Clean Up Infrastructure

When you are finished testing, you can remove all provisioned resources with:

```bash
./destroy.sh
```

This will use Terraform to delete the resource group and everything inside it — VNet, NAT Gateway, Application Gateway, VM Scale Set, autoscale settings, NSGs, and all associated public IPs.
