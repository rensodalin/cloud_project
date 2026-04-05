###############################################################
# modules/monitoring/variables.tf
###############################################################

variable "project_name"   { type = string }
variable "environment"    { type = string }
variable "asg_name"       { type = string }
variable "alb_arn_suffix" { type = string }
variable "tg_arn_suffix"  { type = string }
variable "rds_identifier" { type = string }
variable "alarm_email"    { type = string }
variable "s3_log_bucket"  { type = string }
