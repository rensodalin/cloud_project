###############################################################
# modules/compute/outputs.tf
###############################################################

output "alb_dns_name"   { value = aws_lb.main.dns_name }
output "alb_arn_suffix" { value = aws_lb.main.arn_suffix }
output "tg_arn_suffix"  { value = aws_lb_target_group.app.arn_suffix }
output "asg_name"       { value = aws_autoscaling_group.app.name }
