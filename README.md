# Azure VM Scale Set

This project demonstrates a minimal Azure VM Scale Set (VMSS) deployment using Terraform. It provisions a fleet of Apache web servers behind an Azure Standard Load Balancer, with each instance displaying its own metadata — private IP, VM name, availability zone, and VM size — on a styled page.

Instances run on Standard_B1s Ubuntu VMs and are never directly reachable from the internet. All inbound traffic flows through the load balancer. A NAT Gateway provides outbound internet access for package installation. Azure Monitor autoscale rules drive automatic scale-out and scale-in between 1 and 6 instances based on CPU utilization.

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

[apply.sh](apply.sh) runs `terraform init` and `terraform apply`, then automatically calls [validate.sh](validate.sh) to confirm the deployment is healthy.

---

### Build Results

When the deployment completes, the following resources are created:

- **Networking:**
  - A VNet (10.0.0.0/16) with a single instance subnet (10.0.1.0/24) in centralus
  - NAT Gateway with a static public IP for instance outbound access
  - No public subnet required — the Azure LB frontend is a public IP, not subnet-based

- **Security:**
  - Network Security Group allowing inbound port 80 from the internet
  - NSG associated with the VMSS subnet

- **Load Balancer:**
  - Standard public Azure Load Balancer with a static frontend IP
  - Backend pool that VMSS instances register into automatically
  - HTTP health probe on `/` with 10-second intervals
  - LB rule forwarding port 80 to the backend pool

- **VM Scale Set:**
  - Ubuntu 22.04 LTS, Standard_B1s, spread across availability zones 1 and 2
  - min 1, desired 4, max 6 instances
  - Apache installed via cloud-init; displays Azure IMDS metadata page
  - Azure Monitor autoscale driving scale-out and scale-in on CPU

---

### Scaling Policies

| Rule      | Condition  | Window   | Action      |
|-----------|------------|----------|-------------|
| scale-out | CPU > 60%  | 2 min    | +1 instance |
| scale-in  | CPU < 60%  | 10 min   | -1 instance |

The asymmetric evaluation windows (fast scale-out, slow scale-in) prevent thrashing under brief CPU spikes.

---

### Validate the Deployment

[validate.sh](validate.sh) is called automatically by [apply.sh](apply.sh). It polls the load balancer until it responds, then samples 6 responses to confirm load balancing is working. Different IP addresses across requests confirm that traffic is being distributed across instances.

```
NOTE: LB endpoint: http://20.x.x.x
NOTE: Waiting for HTTP response from load balancer...
NOTE: Load balancer is responding.
NOTE: Sampling LB responses...

  [1] 10.0.1.6
  [2] 10.0.1.8
  [3] 10.0.1.6
  [4] 10.0.1.9
  [5] 10.0.1.8
  [6] 10.0.1.6

=================================================================================
  VM Scale Set — Deployment validated!
=================================================================================
  LB : http://20.x.x.x
=================================================================================
```

---

### Clean Up Infrastructure

When you are finished testing, you can remove all provisioned resources with:

```bash
./destroy.sh
```

This will use Terraform to delete the resource group and everything inside it — VNet, NAT Gateway, load balancer, VM Scale Set, autoscale settings, NSG, and all associated public IPs.
