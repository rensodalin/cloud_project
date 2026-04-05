###############################################################
# modules/compute/main.tf
# ALB + Target Group + ASG + Launch Template + Scaling Policies
###############################################################

###############################################################
# Application Load Balancer
###############################################################
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false  # Set true in production!

  access_logs {
    bucket  = "${var.project_name}-${var.environment}-logs-*"
    prefix  = "alb-logs"
    enabled = false  # Enable after confirming bucket policy setup
  }

  tags = { Name = "${var.project_name}-${var.environment}-alb" }
}

###############################################################
# Target Group
###############################################################
resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-${var.environment}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_subnet.first_public.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = { Name = "${var.project_name}-${var.environment}-tg" }
}

data "aws_subnet" "first_public" {
  id = var.public_subnet_ids[0]
}

###############################################################
# HTTP Listener → redirect to HTTPS if cert provided, else forward
###############################################################
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.certificate_arn != "" ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.certificate_arn != "" ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "forward" {
      for_each = var.certificate_arn == "" ? [1] : []
      content {
        target_group {
          arn    = aws_lb_target_group.app.arn
          weight = 1
        }
      }
    }
  }
}

###############################################################
# HTTPS Listener (only created when certificate_arn is provided)
###############################################################
resource "aws_lb_listener" "https" {
  count             = var.certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

###############################################################
# Launch Template
###############################################################
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-${var.environment}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  dynamic "key_name" {
    for_each = var.key_name != "" ? [var.key_name] : []
    content {}
  }

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.ec2_sg_id]
  }

  monitoring { enabled = true }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    aws_region     = var.aws_region
    s3_bucket_name = var.s3_bucket_name
    db_host        = var.rds_endpoint
    db_name        = var.db_name
    db_user        = var.db_username
    db_pass        = var.db_password
    project_name   = var.project_name
    environment    = var.environment
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.project_name}-${var.environment}-app-server"
      Project = var.project_name
    }
  }

  lifecycle { create_before_destroy = true }
}

###############################################################
# Auto Scaling Group
###############################################################
resource "aws_autoscaling_group" "app" {
  name                      = "${var.project_name}-${var.environment}-asg"
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  vpc_zone_identifier       = var.private_subnet_ids
  health_check_type         = "ELB"
  health_check_grace_period = 300
  force_delete              = false

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app.arn]

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-asg-instance"
    propagate_at_launch = true
  }

  lifecycle { create_before_destroy = true }
}

###############################################################
# Scaling Policies – Target Tracking (CPU)
###############################################################
resource "aws_autoscaling_policy" "cpu_scale_out" {
  name                   = "${var.project_name}-${var.environment}-cpu-scale"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value       = 60.0
    disable_scale_in   = false
  }
}

###############################################################
# Scaling Policy – ALB Request Count per Target
###############################################################
resource "aws_autoscaling_policy" "request_count" {
  name                   = "${var.project_name}-${var.environment}-req-scale"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = 1000.0
  }
}

###############################################################
# Scheduled Scaling – scale down at night (demo / cost saving)
###############################################################
resource "aws_autoscaling_schedule" "scale_down_night" {
  scheduled_action_name  = "scale-down-night"
  min_size               = 1
  max_size               = var.asg_max_size
  desired_capacity       = 1
  recurrence             = "0 20 * * *"  # 8 PM UTC every day
  autoscaling_group_name = aws_autoscaling_group.app.name
}

resource "aws_autoscaling_schedule" "scale_up_morning" {
  scheduled_action_name  = "scale-up-morning"
  min_size               = var.asg_min_size
  max_size               = var.asg_max_size
  desired_capacity       = var.asg_desired_capacity
  recurrence             = "0 8 * * *"  # 8 AM UTC every day
  autoscaling_group_name = aws_autoscaling_group.app.name
}
