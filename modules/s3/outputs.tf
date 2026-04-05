###############################################################
# modules/s3/outputs.tf
###############################################################

output "bucket_name"     { value = aws_s3_bucket.app.bucket }
output "bucket_arn"      { value = aws_s3_bucket.app.arn }
output "log_bucket_name" { value = aws_s3_bucket.logs.bucket }
