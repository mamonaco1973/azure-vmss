# ================================================================================
# Networking
# Two-tier network: public subnets host the ALB; private subnets host instances.
# Instances reach the internet through a NAT gateway and are never directly
# reachable from outside the VPC.
#
# CIDR layout — 10.0.0.0/24 split into four /26 blocks (64 addresses each):
#   10.0.0.0/26   — public  us-east-2a  (ALB)
#   10.0.0.64/26  — public  us-east-2b  (ALB)
#   10.0.0.128/26 — private us-east-2a  (instances)
#   10.0.0.192/26 — private us-east-2b  (instances)
# ================================================================================

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/24"

  # DNS support and hostnames are required for the ALB to resolve instance
  # targets by hostname and for SSM Session Manager to function if needed
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "asg-vpc" }
}

# The IGW is the VPC's on-ramp to the internet — without it, public subnets
# have no path to or from the internet regardless of route table entries
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "asg-igw" }
}

# ================================================================================
# Public Subnets
# The ALB requires subnets in at least two AZs. If one AZ becomes unavailable,
# the ALB continues serving traffic from the other. Instances are NOT placed
# here — public subnets are for the ALB and NAT gateway only.
# ================================================================================

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/26"
  availability_zone = "us-east-2a"

  # Auto-assign public IPs so the NAT gateway EIP association works correctly
  # and the ALB receives a routable address in this AZ
  map_public_ip_on_launch = true

  tags = { Name = "asg-public-us-east-2a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.64/26"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true

  tags = { Name = "asg-public-us-east-2b" }
}

# All internet-bound traffic from public subnets exits through the IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "asg-public-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# ================================================================================
# NAT Gateway
# Sits in a public subnet so it has internet access via the IGW. Private
# instances route outbound traffic here for package installs and AWS API calls.
# Inbound connections from the internet cannot be initiated through a NAT
# gateway — it provides egress-only internet access.
#
# A single NAT gateway is sufficient for this demo. Production deployments
# typically place one per AZ so private instances stay online if an AZ fails.
# ================================================================================

# The EIP gives the NAT gateway a stable, predictable public IP. AWS will not
# reassign this address unless the EIP is explicitly released.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "asg-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  tags = { Name = "asg-nat" }

  # The IGW must exist before the NAT gateway can forward traffic to the
  # internet — explicit dependency prevents a race condition during apply
  depends_on = [aws_internet_gateway.main]
}

# ================================================================================
# Private Subnets
# EC2 instances live here. No public IPs are assigned — all inbound traffic
# arrives through the ALB, and all outbound traffic exits through the NAT
# gateway. Instances are unreachable from the internet by design.
# ================================================================================

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.128/26"
  availability_zone = "us-east-2a"

  # Explicitly false — instances in private subnets must never receive public
  # IPs, even if someone launches one manually outside of Terraform
  map_public_ip_on_launch = false

  tags = { Name = "asg-private-us-east-2a" }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.192/26"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = false

  tags = { Name = "asg-private-us-east-2b" }
}

# All internet-bound traffic from private subnets exits through the NAT gateway
# rather than the IGW — the NAT gateway handles the public IP translation
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "asg-private-rt" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}
