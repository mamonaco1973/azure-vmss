# ================================================================================
# Auto Scaling Group
# The ASG maintains the desired number of instances across both private subnets,
# automatically replacing unhealthy instances and adjusting capacity in response
# to the CloudWatch CPU alarms defined below. Instances are spread across two
# AZs so the application stays available if one AZ has an outage.
# ================================================================================

resource "aws_autoscaling_group" "main" {
  name = "asg-main"

  # Floor of 1 keeps the group alive at minimum cost during quiet periods;
  # ceiling of 6 caps cost during a runaway load event
  min_size         = 1
  max_size         = 6
  desired_capacity = 4

  # Private subnets only — instances are never placed in public subnets.
  # The ASG distributes instances evenly across both AZs automatically.
  vpc_zone_identifier = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  # Registering with the target group allows the ALB to route traffic to new
  # instances as soon as they pass health checks, and stop routing to them
  # when they are terminated during a scale-in event
  target_group_arns = [aws_lb_target_group.main.arn]

  # ELB health type defers to the ALB's own health checks rather than the
  # basic EC2 instance-running check. This means an instance that is up but
  # returning HTTP errors will be replaced, not just an instance that crashed.
  health_check_type = "ELB"

  # Give instances 60 seconds to finish the user_data script and start httpd
  # before the ASG begins health checking. Without this, instances are often
  # terminated and relaunched in a loop during initial deployment.
  health_check_grace_period = 60

  launch_template {
    id = aws_launch_template.main.id

    # $Latest ensures scale-out events always use the most recent template
    # version — avoids stale AMIs or user_data after a template update
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "asg-instance"
    propagate_at_launch = true
  }
}

# ================================================================================
# Scaling Policies
# Each policy adjusts capacity by exactly one instance. Gradual step adjustments
# are safer than percentage-based scaling for small groups — removing 50% of a
# 2-instance group would leave zero capacity. The 120s cooldown prevents the ASG
# from launching a second wave before the first wave has absorbed the load.
# ================================================================================

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "asg-scale-up"
  autoscaling_group_name = aws_autoscaling_group.main.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 120
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "asg-scale-down"
  autoscaling_group_name = aws_autoscaling_group.main.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 120
}

# ================================================================================
# CloudWatch Alarms
# CPU utilization drives all scaling decisions. The asymmetric evaluation periods
# make the group react quickly to rising load (2 periods = 2 min) but wait for
# sustained low load before scaling in (10 periods = 10 min). This prevents
# premature termination of instances during brief CPU dips between bursts.
# ================================================================================

# Triggers scale_up after CPU exceeds 60% for 2 consecutive 1-minute periods
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "asg-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 60

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_up.arn]
}

# Triggers scale_down after CPU stays below 60% for 10 consecutive 1-minute
# periods — the longer window avoids removing instances too eagerly
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "asg-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 10
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 60

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_down.arn]
}
