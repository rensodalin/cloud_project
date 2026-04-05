###############################################################
# modules/compute/variables.tf
###############################################################

variable "project_name"         { type = string }
variable "environment"          { type = string }
variable "aws_region"           { type = string }
variable "ami_id"               { type = string }
variable "instance_type"        { type = string }
variable "key_name"             { type = string; default = "" }
variable "public_subnet_ids"    { type = list(string) }
variable "private_subnet_ids"   { type = list(string) }
variable "ec2_sg_id"            { type = string }
variable "alb_sg_id"            { type = string }
variable "iam_instance_profile" { type = string }
variable "s3_bucket_name"       { type = string }
variable "rds_endpoint"         { type = string }
variable "db_name"              { type = string }
variable "db_username"          { type = string; sensitive = true }
variable "db_password"          { type = string; sensitive = true }
variable "asg_min_size"         { type = number }
variable "asg_max_size"         { type = number }
variable "asg_desired_capacity" { type = number }
variable "health_check_path"    { type = string; default = "/" }
variable "certificate_arn"      { type = string; default = "" }
