# ================================================================================
# Application Load Balancer
# The ALB is the single public entry point for the application. It distributes
# incoming HTTP requests across healthy instances in both AZs, performs health
# checks to detect failed instances, and removes them from rotation
# automatically. Clients always talk to the ALB — never directly to instances.
# ================================================================================

# internal = false gives the ALB a public DNS name and places it in the public
# subnets so it is reachable from the internet
resource "aws_lb" "main" {
  name               = "asg-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]

  # Two subnets in different AZs are required — the ALB will refuse to create
  # with only one subnet, as it needs redundancy across availability zones
  subnets = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = { Name = "asg-alb" }
}

# The target group is the pool of instances the ALB routes traffic to.
# The ASG registers and deregisters instances here as it scales in and out.
resource "aws_lb_target_group" "main" {
  name     = "asg-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    # Apache serves the welcome page at / — a 200 response means httpd is up
    path = "/"

    # Check every 10 seconds — fast enough to detect failures within a minute
    interval = 10

    # Require 3 consecutive successes before marking healthy, preventing a
    # slow-starting instance from receiving traffic before httpd is ready
    healthy_threshold = 3

    # Only 2 consecutive failures needed to pull an instance from rotation —
    # quicker response to failed instances keeps error rates low
    unhealthy_threshold = 2
  }

  tags = { Name = "asg-tg" }
}

# The listener watches port 80 and forwards all requests to the target group.
# More advanced setups add rules here for path-based routing or HTTPS redirect.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}
