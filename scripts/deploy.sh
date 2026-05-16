#!/usr/bin/env bash
# deploy.sh
#
# Deploys the EasyAuth demo to Azure App Service.
# Reads parameters from infra/main.parameters.local.json (written by setup-app-registration.sh).
#
# Usage:
#   ./scripts/deploy.sh --resource-group <RG_NAME> [--location westus2]
#
# Prerequisites:
#   az login
#   Run scripts/setup-app-registration.sh first
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RG=""
LOCATION="westus2"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group) RG="$2";       shift 2 ;;
    --location)       LOCATION="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

[[ -z "$RG" ]] && {
  echo "Usage: $0 --resource-group <RG_NAME> [--location westus2]"
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCAL_PARAMS="${REPO_ROOT}/infra/main.parameters.local.json"

[[ ! -f "$LOCAL_PARAMS" ]] && {
  echo "❌  ${LOCAL_PARAMS} not found."
  echo "    Run ./scripts/setup-app-registration.sh first."
  exit 1
}

APP_NAME=$(jq -r '.parameters.appName.value' "${LOCAL_PARAMS}")

# ── 1. Resource group ─────────────────────────────────────────────────────────
echo "📦  Ensuring resource group '${RG}' in '${LOCATION}'..."
az group create --name "${RG}" --location "${LOCATION}" --output none

# ── 2. Bicep deployment ───────────────────────────────────────────────────────
echo "🏗️   Deploying Bicep template..."
az deployment group create \
  --resource-group "${RG}" \
  --template-file "${REPO_ROOT}/infra/main.bicep" \
  --parameters "${LOCAL_PARAMS}" \
  --parameters location="${LOCATION}" \
  --output table

# ── 3. Zip and deploy app code ────────────────────────────────────────────────
echo "🗜️   Zipping application..."
cd "${REPO_ROOT}"
ZIP_FILE="/tmp/easyauth-demo.zip"
zip -r "${ZIP_FILE}" app requirements.txt gunicorn.conf.py \
  --exclude "app/__pycache__/*" --exclude "app/**/__pycache__/*" >/dev/null

echo "🚀  Deploying app code to '${APP_NAME}'..."
az webapp deploy \
  --resource-group "${RG}" \
  --name "${APP_NAME}" \
  --src-path "${ZIP_FILE}" \
  --type zip \
  --async false

rm -f "${ZIP_FILE}"

HOSTNAME=$(az webapp show --resource-group "${RG}" --name "${APP_NAME}" \
  --query defaultHostName -o tsv)

echo ""
echo "✅  Deployment complete!"
echo "   App URL: https://${HOSTNAME}"
echo ""
echo "Tip: Assign roles to demo users with:"
echo "   ./scripts/assign-roles.sh --app-id <CLIENT_ID> --upn <user@domain.com> --role User|Premium|Admin"
