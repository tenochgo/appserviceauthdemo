#!/usr/bin/env bash
# setup-app-registration.sh
#
# Creates (or re-uses) a Microsoft Entra App Registration for the EasyAuth demo,
# adds the three App Roles (User, Premium, Admin), generates a client secret, and
# writes the values to infra/main.parameters.local.json (gitignored).
#
# Prerequisites:
#   az login && az account set --subscription <SUBSCRIPTION_ID>
#   jq installed  (brew install jq)
#
# Usage:
#   ./scripts/setup-app-registration.sh --app-name easyauth-demo --app-service-hostname easyauth-demo.azurewebsites.net
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

APP_NAME=""
HOSTNAME=""

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-name)         APP_NAME="$2";   shift 2 ;;
    --app-service-hostname) HOSTNAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

[[ -z "$APP_NAME" || -z "$HOSTNAME" ]] && {
  echo "Usage: $0 --app-name <name> --app-service-hostname <host>"
  exit 1
}

REDIRECT_URI="https://${HOSTNAME}/.auth/login/aad/callback"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PARAMS_FILE="${REPO_ROOT}/infra/main.parameters.local.json"

echo "🔍  Looking for existing App Registration: ${APP_NAME}"

# ── Get or create App Registration ───────────────────────────────────────────
APP_ID=$(az ad app list --display-name "${APP_NAME}" --query "[0].appId" -o tsv 2>/dev/null || true)

if [[ -z "$APP_ID" || "$APP_ID" == "None" ]]; then
  echo "📝  Creating App Registration..."
  APP_ID=$(az ad app create \
    --display-name "${APP_NAME}" \
    --sign-in-audience AzureADMyOrg \
    --web-redirect-uris "${REDIRECT_URI}" \
    --query appId -o tsv)
  echo "   Created app: ${APP_ID}"
else
  echo "   Found existing app: ${APP_ID}"
  # Ensure redirect URI is present
  az ad app update --id "${APP_ID}" \
    --web-redirect-uris "${REDIRECT_URI}" >/dev/null
fi

OBJECT_ID=$(az ad app show --id "${APP_ID}" --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

# ── Set accessTokenAcceptedVersion = 2 (v2 tokens) ───────────────────────────
echo "🔧  Setting accessTokenAcceptedVersion to 2..."
az ad app update --id "${APP_ID}" \
  --set "api={\"requestedAccessTokenVersion\":2}" >/dev/null 2>&1 || true

# ── Define App Roles (idempotent PATCH) ───────────────────────────────────────
echo "🎭  Configuring App Roles (User, Premium, Admin)..."

APP_ROLES_JSON=$(cat <<'EOF'
[
  {
    "id": "a1b2c3d4-0001-0001-0001-000000000001",
    "allowedMemberTypes": ["User"],
    "description": "Regular user with access to authenticated content.",
    "displayName": "Regular User",
    "isEnabled": true,
    "value": "User"
  },
  {
    "id": "a1b2c3d4-0002-0002-0002-000000000002",
    "allowedMemberTypes": ["User"],
    "description": "Premium user with access to premium features.",
    "displayName": "Premium User",
    "isEnabled": true,
    "value": "Premium"
  },
  {
    "id": "a1b2c3d4-0003-0003-0003-000000000003",
    "allowedMemberTypes": ["User"],
    "description": "Administrator with full access including the admin panel.",
    "displayName": "Admin",
    "isEnabled": true,
    "value": "Admin"
  }
]
EOF
)

az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/${OBJECT_ID}" \
  --headers "Content-Type=application/json" \
  --body "{\"appRoles\": ${APP_ROLES_JSON}}" >/dev/null

echo "   App Roles patched."

# ── Create client secret ───────────────────────────────────────────────────────
echo "🔑  Creating client secret (valid 2 years)..."
SECRET_JSON=$(az ad app credential reset \
  --id "${APP_ID}" \
  --years 2 \
  --query "{secret:password}" -o json)
CLIENT_SECRET=$(echo "${SECRET_JSON}" | jq -r '.secret')
echo "   Secret created."

# ── Create / update Enterprise App (service principal) ────────────────────────
echo "🏢  Ensuring enterprise application (service principal) exists..."
SP_EXISTS=$(az ad sp list --filter "appId eq '${APP_ID}'" --query "[0].id" -o tsv 2>/dev/null || true)
if [[ -z "$SP_EXISTS" || "$SP_EXISTS" == "None" ]]; then
  SP_OBJECT_ID=$(az ad sp create --id "${APP_ID}" --query id -o tsv)
  echo "   Service principal created: ${SP_OBJECT_ID}"
else
  SP_OBJECT_ID="$SP_EXISTS"
  echo "   Service principal exists: ${SP_OBJECT_ID}"
fi

# Require role assignment (only assigned users/groups can sign in)
echo "🔒  Setting appRoleAssignmentRequired = true..."
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${SP_OBJECT_ID}" \
  --headers "Content-Type=application/json" \
  --body '{"appRoleAssignmentRequired": true}' >/dev/null

# ── Write parameters file ─────────────────────────────────────────────────────
echo "💾  Writing ${PARAMS_FILE}..."
cat >"${PARAMS_FILE}" <<EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "appName":         { "value": "${APP_NAME}" },
    "aadTenantId":     { "value": "${TENANT_ID}" },
    "aadClientId":     { "value": "${APP_ID}" },
    "aadClientSecret": { "value": "${CLIENT_SECRET}" },
    "planSku":         { "value": "B1" }
  }
}
EOF

echo ""
echo "✅  App Registration setup complete."
echo "   App ID (clientId): ${APP_ID}"
echo "   Tenant ID:         ${TENANT_ID}"
echo "   SP Object ID:      ${SP_OBJECT_ID}"
echo ""
echo "   Parameters written to: ${PARAMS_FILE}"
echo "   ⚠️  This file contains a client secret — DO NOT commit it."
echo ""
echo "Next step: run ./scripts/assign-roles.sh to assign roles to demo users."
