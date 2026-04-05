###############################################################
# modules/rds/variables.tf
###############################################################

variable "project_name"      { type = string }
variable "environment"       { type = string }
variable "db_subnet_group"   { type = string }
variable "db_security_group" { type = string }
variable "db_name"           { type = string }
variable "db_username"       { type = string; sensitive = true }
variable "db_password"       { type = string; sensitive = true }
variable "db_instance_class" { type = string }
