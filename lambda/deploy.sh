#!/usr/bin/env bash
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
FUNCTION_NAME="meteo-alert-checker"
ROLE_NAME="meteo-alert-lambda-role"
RULE_NAME="meteo-alert-hourly"
RUNTIME="python3.12"
HANDLER="index.handler"
TIMEOUT=300
MEMORY=256
REGION="${AWS_DEFAULT_REGION:-eu-west-1}"
DB_URL="https://meteo-alert-409a8-default-rtdb.europe-west1.firebasedatabase.app"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
ZIP_PATH="$SCRIPT_DIR/function.zip"
SA_FILE="$SCRIPT_DIR/firebase-service-account.json"

# ── Helpers ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}▶ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
die()  { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }

# ── Prerequisites ─────────────────────────────────────────────────────────────
command -v aws     >/dev/null || die "aws CLI not found. Install: https://aws.amazon.com/cli/"
command -v pip3    >/dev/null || die "pip3 not found."
command -v python3 >/dev/null || die "python3 not found."
aws sts get-caller-identity >/dev/null || die "AWS credentials not configured. Run: aws configure"

[[ -f "$SA_FILE" ]] || die "Missing firebase-service-account.json in lambda/\n  → Firebase Console → Project settings → Service accounts → Generate new private key"

SA_JSON=$(cat "$SA_FILE" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)))")

# ── Build zip ─────────────────────────────────────────────────────────────────
log "Building deployment package..."
rm -rf "$BUILD_DIR" "$ZIP_PATH"
mkdir -p "$BUILD_DIR"
pip3 install -r "$SCRIPT_DIR/requirements.txt" -t "$BUILD_DIR" -q \
  --platform manylinux2014_x86_64 --only-binary=:all: 2>/dev/null \
  || pip3 install -r "$SCRIPT_DIR/requirements.txt" -t "$BUILD_DIR" -q
cp "$SCRIPT_DIR/index.py" "$BUILD_DIR/"
(cd "$BUILD_DIR" && zip -r "$ZIP_PATH" . -q)
SIZE=$(du -sh "$ZIP_PATH" | cut -f1)
log "Package ready: function.zip ($SIZE)"

# ── IAM role ──────────────────────────────────────────────────────────────────
log "Checking IAM role..."
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" \
  --query 'Role.Arn' --output text 2>/dev/null || echo "")

if [[ -z "$ROLE_ARN" ]]; then
  log "Creating IAM role $ROLE_NAME..."
  TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
  ROLE_ARN=$(aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST" \
    --query 'Role.Arn' --output text)
  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  log "Role created. Waiting for propagation..."
  sleep 12
else
  log "Role exists: $ROLE_ARN"
fi

# ── Lambda ────────────────────────────────────────────────────────────────────
ENV_VARS="Variables={FIREBASE_SERVICE_ACCOUNT=$SA_JSON,FIREBASE_DATABASE_URL=$DB_URL}"

FUNCTION_EXISTS=$(aws lambda get-function --function-name "$FUNCTION_NAME" \
  --region "$REGION" --query 'Configuration.FunctionArn' --output text 2>/dev/null || echo "")

if [[ -z "$FUNCTION_EXISTS" ]]; then
  log "Creating Lambda function..."
  FUNCTION_ARN=$(aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --role "$ROLE_ARN" \
    --handler "$HANDLER" \
    --zip-file "fileb://$ZIP_PATH" \
    --timeout "$TIMEOUT" \
    --memory-size "$MEMORY" \
    --environment "$ENV_VARS" \
    --region "$REGION" \
    --query 'FunctionArn' --output text)
  log "Lambda created: $FUNCTION_ARN"
else
  log "Updating Lambda code..."
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$ZIP_PATH" \
    --region "$REGION" >/dev/null
  aws lambda wait function-updated \
    --function-name "$FUNCTION_NAME" --region "$REGION"
  log "Updating Lambda config..."
  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --timeout "$TIMEOUT" \
    --memory-size "$MEMORY" \
    --environment "$ENV_VARS" \
    --region "$REGION" >/dev/null
  FUNCTION_ARN="$FUNCTION_EXISTS"
  log "Lambda updated."
fi

# ── EventBridge rule ──────────────────────────────────────────────────────────
log "Checking EventBridge rule..."
RULE_ARN=$(aws events describe-rule --name "$RULE_NAME" --region "$REGION" \
  --query 'Arn' --output text 2>/dev/null || echo "")

if [[ -z "$RULE_ARN" ]]; then
  log "Creating EventBridge rule (every 1 hour)..."
  RULE_ARN=$(aws events put-rule \
    --name "$RULE_NAME" \
    --schedule-expression "rate(1 hour)" \
    --state ENABLED \
    --region "$REGION" \
    --query 'RuleArn' --output text)
fi

# Allow EventBridge to invoke Lambda (idempotent: ignore if already exists)
aws lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id "allow-eventbridge" \
  --action "lambda:InvokeFunction" \
  --principal "events.amazonaws.com" \
  --source-arn "$RULE_ARN" \
  --region "$REGION" 2>/dev/null || true

# Set Lambda as the rule target
aws events put-targets \
  --rule "$RULE_NAME" \
  --targets "Id=1,Arn=$FUNCTION_ARN" \
  --region "$REGION" >/dev/null

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}✓ Deploy complete!${NC}"
echo ""
echo "  Function : $FUNCTION_ARN"
echo "  Schedule : every 1 hour"
echo "  Region   : $REGION"
echo ""
echo "Test now:"
echo "  aws lambda invoke --function-name $FUNCTION_NAME --region $REGION /tmp/out.json && cat /tmp/out.json"
echo ""
echo "View logs:"
echo "  aws logs tail /aws/lambda/$FUNCTION_NAME --follow --region $REGION"
