###############################################################
# modules/monitoring/main.tf
# CloudWatch Dashboard, Alarms, SNS Topic, and Log Groups
###############################################################

###############################################################
# SNS Topic for alarm notifications
###############################################################
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"
  tags = { Name = "${var.project_name}-${var.environment}-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

###############################################################
# CloudWatch Log Groups
###############################################################
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/ec2/${var.project_name}-${var.environment}/app"
  retention_in_days = 30
  tags              = { Name = "app-logs" }
}

resource "aws_cloudwatch_log_group" "httpd_access" {
  name              = "/aws/ec2/${var.project_name}-${var.environment}/httpd/access"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "httpd_error" {
  name              = "/aws/ec2/${var.project_name}-${var.environment}/httpd/error"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "rds" {
  name              = "/aws/rds/instance/${var.rds_identifier}/error"
  retention_in_days = 30
}

###############################################################
# Alarms – EC2 / ASG
###############################################################

# HIGH CPU – triggers scale-out alarm
resource "aws_cloudwatch_metric_alarm" "asg_high_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Average CPU utilisation exceeds 70% – ASG will scale out"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "missing"

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
}

# LOW CPU – alert for potential over-provisioning
resource "aws_cloudwatch_metric_alarm" "asg_low_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-low-cpu"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 10
  alarm_description   = "Average CPU utilisation below 10% – consider scaling in"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "missing"

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
}

###############################################################
# Alarms – ALB
###############################################################

# High 5XX error rate
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-5xx"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 50
  alarm_description   = "ALB 5XX errors exceeded 50 in 1 minute"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

# High target response time
resource "aws_cloudwatch_metric_alarm" "alb_response_time" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-latency"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 2
  alarm_description   = "Average ALB response time > 2s"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.tg_arn_suffix
  }
}

# Unhealthy hosts
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project_name}-${var.environment}-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "At least 1 unhealthy EC2 target in the ALB – ASG should auto-replace"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.tg_arn_suffix
  }
}

###############################################################
# Alarms – RDS
###############################################################

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU exceeds 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = var.rds_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-low-storage"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Minimum"
  threshold           = 5368709120  # 5 GB in bytes
  alarm_description   = "RDS free storage space below 5 GB"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = var.rds_identifier
  }
}

###############################################################
# CloudWatch Dashboard
###############################################################
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "text"
        x = 0; y = 0; width = 24; height = 1
        properties = {
          markdown = "## ${var.project_name} – ${var.environment} Dashboard"
        }
      },
      {
        type = "metric"
        x = 0; y = 1; width = 8; height = 6
        properties = {
          title  = "ASG – CPU Utilization"
          period = 60
          stat   = "Average"
          metrics = [[
            "AWS/EC2", "CPUUtilization",
            "AutoScalingGroupName", var.asg_name
          ]]
          view = "timeSeries"
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric"
        x = 8; y = 1; width = 8; height = 6
        properties = {
          title  = "ALB – Request Count"
          period = 60
          stat   = "Sum"
          metrics = [[
            "AWS/ApplicationELB", "RequestCount",
            "LoadBalancer", var.alb_arn_suffix
          ]]
          view = "timeSeries"
        }
      },
      {
        type = "metric"
        x = 16; y = 1; width = 8; height = 6
        properties = {
          title  = "ALB – Healthy / Unhealthy Hosts"
          period = 60
          stat   = "Minimum"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount",
             "LoadBalancer", var.alb_arn_suffix,
             "TargetGroup", var.tg_arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount",
             "LoadBalancer", var.alb_arn_suffix,
             "TargetGroup", var.tg_arn_suffix]
          ]
          view = "timeSeries"
        }
      },
      {
        type = "metric"
        x = 0; y = 7; width = 8; height = 6
        properties = {
          title  = "ALB – 4XX / 5XX Errors"
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_4XX_Count",
             "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count",
             "LoadBalancer", var.alb_arn_suffix]
          ]
          view = "timeSeries"
        }
      },
      {
        type = "metric"
        x = 8; y = 7; width = 8; height = 6
        properties = {
          title  = "RDS – CPU Utilization"
          period = 60
          stat   = "Average"
          metrics = [[
            "AWS/RDS", "CPUUtilization",
            "DBInstanceIdentifier", var.rds_identifier
          ]]
          view = "timeSeries"
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric"
        x = 16; y = 7; width = 8; height = 6
        properties = {
          title  = "RDS – Free Storage Space (GB)"
          period = 300
          stat   = "Minimum"
          metrics = [[
            "AWS/RDS", "FreeStorageSpace",
            "DBInstanceIdentifier", var.rds_identifier
          ]]
          view = "timeSeries"
        }
      },
      {
        type = "metric"
        x = 0; y = 13; width = 8; height = 6
        properties = {
          title  = "ALB – Target Response Time (s)"
          period = 60
          stat   = "Average"
          metrics = [[
            "AWS/ApplicationELB", "TargetResponseTime",
            "LoadBalancer", var.alb_arn_suffix
          ]]
          view = "timeSeries"
        }
      }
    ]
  })
}
