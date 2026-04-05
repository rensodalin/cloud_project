#!/usr/bin/env bash
###############################################################
# simulate_failure.sh
# Demonstrate ASG auto-recovery by terminating an instance.
# Usage: ./scripts/simulate_failure.sh [aws-region]
###############################################################
set -euo pipefail

REGION="${1:-us-east-1}"
ASG_NAME=$(terraform output -raw asg_name 2>/dev/null || echo "")

if [ -z "$ASG_NAME" ]; then
  echo "❌ Could not get ASG name. Run from the Terraform root directory."
  exit 1
fi

echo "========================================"
echo " ASG Failure Simulation"
echo " ASG: $ASG_NAME | Region: $REGION"
echo "========================================"

# Get running instances in the ASG
INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --region "$REGION" \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
  --output text)

if [ -z "$INSTANCES" ]; then
  echo "❌ No InService instances found in ASG."
  exit 1
fi

# Pick the first instance to terminate
TARGET=$(echo "$INSTANCES" | awk '{print $1}')

echo ""
echo "📋 Running instances in ASG:"
echo "$INSTANCES"
echo ""
echo "💣 Terminating instance: $TARGET"
echo ""

aws ec2 terminate-instances \
  --instance-ids "$TARGET" \
  --region "$REGION" \
  --output table

echo ""
echo "⏳ Waiting 30 seconds, then polling ASG for replacement..."
sleep 30

for i in {1..10}; do
  STATUS=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region "$REGION" \
    --query 'AutoScalingGroups[0].Instances[*].{ID:InstanceId,State:LifecycleState}' \
    --output table)
  echo "--- Attempt $i ---"
  echo "$STATUS"
  echo ""

  # Check if desired capacity is met with healthy instances
  HEALTHY=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region "$REGION" \
    --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`] | length(@)' \
    --output text)

  DESIRED=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region "$REGION" \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text)

  echo "✅ Healthy: $HEALTHY / Desired: $DESIRED"

  if [ "$HEALTHY" -ge "$DESIRED" ]; then
    echo ""
    echo "✅ Auto-recovery confirmed! ASG replaced the terminated instance."
    exit 0
  fi

  echo "⏳ Waiting 30 more seconds..."
  sleep 30
done

echo ""
echo "⚠️  ASG recovery taking longer than expected. Check AWS Console."
