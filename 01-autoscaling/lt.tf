# ================================================================================
# Launch Template
# Defines the blueprint for every EC2 instance the ASG creates. When the ASG
# scales out it launches new instances from the latest version of this template,
# so changes here (new AMI, updated user_data) take effect on the next scale-out
# without needing to replace existing instances.
# ================================================================================

resource "aws_launch_template" "main" {
  # name_prefix lets AWS append a unique suffix on every recreate — without it,
  # Terraform cannot create the replacement before deleting the original because
  # the name would collide
  name_prefix   = "asg-lt-"
  image_id      = data.aws_ami.al2023.id
  instance_type = "t4g.micro"

  network_interfaces {
    # Instances live in private subnets and must not receive public IPs —
    # all inbound traffic arrives through the ALB, never directly
    associate_public_ip_address = false
    security_groups             = [aws_security_group.instance.id]
  }

  # filebase64 reads and encodes the script in one step — keeps the HTML/bash
  # out of the Terraform files without needing a templatefile() wrapper
  user_data = filebase64("${path.module}/scripts/userdata.sh")

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "asg-instance" }
  }
}
