#!/usr/bin/env bash
# assign-roles.sh
#
# Assigns an Entra ID user to an App Role on the EasyAuth demo enterprise app.
#
# Usage:
#   ./scripts/assign-roles.sh --app-id <CLIENT_ID> --upn user@contoso.com --role User|Premium|Admin
#
# Prerequisites:
#   az login  (account must have User.ReadWrite or directory admin rights to assign app roles)
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

APP_ID=""
UPN=""
ROLE_VALUE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-id) APP_ID="$2"; shift 2 ;;
    --upn)    UPN="$2";    shift 2 ;;
    --role)   ROLE_VALUE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

[[ -z "$APP_ID" || -z "$UPN" || -z "$ROLE_VALUE" ]] && {
  echo "Usage: $0 --app-id <clientId> --upn <user@domain.com> --role <User|Premium|Admin>"
  exit 1
}

# Lookup service principal object ID
SP_OBJECT_ID=$(az ad sp list --filter "appId eq '${APP_ID}'" --query "[0].id" -o tsv)
[[ -z "$SP_OBJECT_ID" || "$SP_OBJECT_ID" == "None" ]] && {
  echo "❌  Service principal not found for appId ${APP_ID}. Did you run setup-app-registration.sh?"
  exit 1
}

# Lookup the App Role ID by its value string
APP_ROLE_ID=$(az ad sp show --id "${SP_OBJECT_ID}" \
  --query "appRoles[?value=='${ROLE_VALUE}'].id" -o tsv 2>/dev/null || true)

[[ -z "$APP_ROLE_ID" || "$APP_ROLE_ID" == "None" ]] && {
  echo "❌  App Role '${ROLE_VALUE}' not found on service principal ${SP_OBJECT_ID}."
  echo "    Valid values: User, Premium, Admin"
  exit 1
}

# Lookup user object ID
USER_OBJECT_ID=$(az ad user show --id "${UPN}" --query id -o tsv)
[[ -z "$USER_OBJECT_ID" ]] && { echo "❌  User not found: ${UPN}"; exit 1; }

echo "🔗  Assigning role '${ROLE_VALUE}' to ${UPN}..."
echo "   User Object ID:  ${USER_OBJECT_ID}"
echo "   SP Object ID:    ${SP_OBJECT_ID}"
echo "   App Role ID:     ${APP_ROLE_ID}"

# Check for existing assignment (avoid duplicate)
EXISTING=$(az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/users/${USER_OBJECT_ID}/appRoleAssignments" \
  --query "value[?appRoleId=='${APP_ROLE_ID}' && resourceId=='${SP_OBJECT_ID}'].id" \
  -o tsv 2>/dev/null || true)

if [[ -n "$EXISTING" && "$EXISTING" != "None" ]]; then
  echo "   ✅  Role already assigned (id: ${EXISTING}). Nothing to do."
  exit 0
fi

az rest --method POST \
  --uri "https://graph.microsoft.com/v1.0/users/${USER_OBJECT_ID}/appRoleAssignments" \
  --headers "Content-Type=application/json" \
  --body "{
    \"principalId\": \"${USER_OBJECT_ID}\",
    \"resourceId\":  \"${SP_OBJECT_ID}\",
    \"appRoleId\":   \"${APP_ROLE_ID}\"
  }" >/dev/null

echo "✅  Role '${ROLE_VALUE}' assigned to ${UPN}."
