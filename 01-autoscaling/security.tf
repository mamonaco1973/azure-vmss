# ================================================================================
# Security Groups
# Two-tier model: the ALB faces the internet and accepts HTTP from anywhere;
# instances only accept traffic sourced from the ALB security group. This means
# an instance is unreachable directly from the internet even though it sits in
# a VPC with an IGW — the security group is the enforcement point.
# ================================================================================

# The ALB is the sole public entry point. Port 80 is open to the world so that
# any browser can reach the application without needing to know instance IPs.
resource "aws_security_group" "alb" {
  name        = "asg-alb-sg"
  description = "Allow HTTP inbound to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Unrestricted egress lets the ALB forward requests to instances and receive
  # health-check responses — the ALB itself initiates these outbound connections
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "asg-alb-sg" }
}

# Using a security group reference instead of a CIDR means only traffic that
# literally passed through the ALB security group can reach instances.
# Adding your laptop's IP to the ALB CIDR would not grant direct instance
# access — the instance SG would still block it.
resource "aws_security_group" "instance" {
  name        = "asg-instance-sg"
  description = "Allow HTTP from ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Unrestricted egress allows instances to reach yum repos and AWS APIs
  # through the NAT gateway — no specific destination needs to be whitelisted
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "asg-instance-sg" }
}
