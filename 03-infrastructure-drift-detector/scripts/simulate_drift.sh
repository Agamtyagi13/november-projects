#!/usr/bin/env bash
# Introduces out-of-band changes in LocalStack (like someone clicking in the console).
# Needs: aws cli. Usage: ./scripts/simulate_drift.sh
set -euo pipefail
EP="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
aws --endpoint-url "$EP" s3api put-bucket-tagging --bucket drift-demo-app-data \
  --tagging 'TagSet=[{Key=Project,Value=drift-demo},{Key=Owner,Value=someone-else},{Key=Debug,Value=true}]'
aws --endpoint-url "$EP" s3api put-bucket-versioning --bucket drift-demo-app-data --versioning-configuration Status=Suspended
QURL="$(aws --endpoint-url "$EP" sqs get-queue-url --queue-name drift-demo-jobs --query QueueUrl --output text)"
aws --endpoint-url "$EP" sqs set-queue-attributes --queue-url "$QURL" --attributes VisibilityTimeout=999
echo "Drift introduced: bucket tags, bucket versioning, queue visibility timeout."
