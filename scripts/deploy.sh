#!/usr/bin/env bash
###############################################################
# deploy.sh
# Wrapper that runs: init → validate → plan → apply
###############################################################
set -euo pipefail

echo "🚀 Starting Terraform deployment..."
echo ""

# Validate tfvars exists
if [ ! -f "terraform.tfvars" ]; then
  echo "❌ terraform.tfvars not found."
  echo "  Copy terraform.tfvars.example → terraform.tfvars and fill in your values."
  exit 1
fi

terraform init -upgrade
terraform validate
terraform fmt -recursive
terraform plan  -out=tfplan
terraform apply tfplan

echo ""
echo "✅ Deployment complete!"
echo ""
echo "ALB DNS: $(terraform output -raw alb_dns_name)"
echo ""
echo "Access your app at: http://$(terraform output -raw alb_dns_name)"
