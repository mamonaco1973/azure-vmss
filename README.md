# AWS Auto Scaling

This project demonstrates a minimal AWS Auto Scaling Group deployment using Terraform. It provisions a fleet of Apache web servers behind an Application Load Balancer, with each instance displaying its own metadata — private IP, instance ID, availability zone, and instance type — on a styled page.

Instances run on ARM-based t4g.micro (Graviton2) in private subnets and are never directly reachable from the internet. All inbound traffic flows through the ALB. A NAT Gateway provides outbound internet access for package installation. CPU-based CloudWatch alarms drive automatic scale-out and scale-in between 1 and 6 instances.

This solution is ideal for understanding the fundamentals of AWS Auto Scaling without the complexity of application-specific configuration. It uses no Packer, no custom AMI, and deploys in a single Terraform phase.

## Prerequisites

* [An AWS Account](https://aws.amazon.com/console/)
* [Install AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
* [Install Latest Terraform](https://developer.hashicorp.com/terraform/install)

If this is your first time watching our content, we recommend starting with this video: [AWS + Terraform: Easy Setup](https://youtu.be/BCMQo0CB9wk). It provides a step-by-step guide to properly configure Terraform and the AWS CLI.

---

## Download this Repository

```bash
git clone https://github.com/mamonaco1973/aws-autoscaling.git
cd aws-autoscaling
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
  - A VPC (10.0.0.0/24) with public and private subnets across us-east-2a and us-east-2b
  - Internet Gateway for ALB inbound traffic
  - NAT Gateway in the public subnet for instance outbound access
  - Route tables configured for both public and private subnets

- **Security:**
  - ALB security group: accepts port 80 from the internet
  - Instance security group: accepts port 80 only from the ALB security group

- **Load Balancer:**
  - Internet-facing Application Load Balancer in the public subnets
  - Target group with HTTP health checks on `/`
  - HTTP listener forwarding to the target group

- **Auto Scaling:**
  - Launch Template: Amazon Linux 2023 ARM64, t4g.micro, Apache with IMDSv2 metadata page
  - Auto Scaling Group: min 1, desired 4, max 6 — spread across private subnets
  - Scale-up policy: +1 instance, 120-second cooldown
  - Scale-down policy: -1 instance, 120-second cooldown
  - CloudWatch alarms driving both policies based on average CPU utilization

---

### Scaling Policies

| Alarm    | Condition  | Periods    | Action      |
|----------|------------|------------|-------------|
| cpu-high | CPU > 60%  | 2 × 1 min  | +1 instance |
| cpu-low  | CPU < 60%  | 10 × 1 min | -1 instance |

The asymmetric period counts (fast scale-up, slow scale-down) prevent thrashing under brief CPU spikes.

---

### Validate the Deployment

[validate.sh](validate.sh) is called automatically by [apply.sh](apply.sh). It waits for at least one healthy target in the ALB target group, then samples 6 responses to confirm load balancing is working. Different IP addresses across requests confirm that traffic is being distributed across instances.

```
NOTE: ALB endpoint: http://asg-alb-xxxxxxxxxx.us-east-2.elb.amazonaws.com
NOTE: Waiting for healthy targets in asg-tg...
NOTE: 4 healthy target(s) registered.
NOTE: Sampling ALB responses...

  [1] 10.0.0.221
  [2] 10.0.0.134
  [3] 10.0.0.221
  [4] 10.0.0.134
  [5] 10.0.0.221
  [6] 10.0.0.134

=================================================================================
  Auto Scaling Group — Deployment validated!
=================================================================================
  ALB : http://asg-alb-xxxxxxxxxx.us-east-2.elb.amazonaws.com
=================================================================================
```

---

### Clean Up Infrastructure

When you are finished testing, you can remove all provisioned resources with:

```bash
./destroy.sh
```

This will use Terraform to delete the VPC, subnets, NAT Gateway, ALB, Auto Scaling Group, Launch Template, security groups, CloudWatch alarms, and all other infrastructure created by the project.
