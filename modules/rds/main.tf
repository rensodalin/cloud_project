###############################################################
# modules/rds/main.tf
# Multi-AZ MySQL RDS instance in private subnets
###############################################################

resource "aws_db_instance" "main" {
  identifier              = "${var.project_name}-${var.environment}-mysql"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  max_allocated_storage   = 100
  storage_type            = "gp3"
  storage_encrypted       = true
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = var.db_subnet_group
  vpc_security_group_ids  = [var.db_security_group]
  multi_az                = true
  publicly_accessible     = false
  deletion_protection     = false   # Set true in production!
  skip_final_snapshot     = true    # Set false in production!
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  # Enable Enhanced Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Enable Performance Insights
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # Enable CloudWatch log exports
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

  tags = { Name = "${var.project_name}-${var.environment}-mysql" }
}

###############################################################
# IAM role for RDS Enhanced Monitoring
###############################################################
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

###############################################################
# RDS Parameter Group
###############################################################
resource "aws_db_parameter_group" "main" {
  name   = "${var.project_name}-${var.environment}-mysql8"
  family = "mysql8.0"

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  tags = { Name = "${var.project_name}-${var.environment}-mysql8-params" }
}
