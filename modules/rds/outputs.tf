###############################################################
# modules/rds/outputs.tf
###############################################################

output "db_endpoint"   { value = aws_db_instance.main.endpoint }
output "db_identifier" { value = aws_db_instance.main.identifier }
output "db_port"       { value = aws_db_instance.main.port }
