# Azure App Service Easy Auth + App Roles Demo

A sleek Flask demo that shows how **Azure App Service Easy Auth** (Microsoft Entra provider) combined with **App Registration App Roles** delivers role-based access control — with zero token-validation code in your app.

```
┌─────────────────────────────────────────────────────────────┐
│  Browser                                                    │
└────────────────────────┬────────────────────────────────────┘
                         │ HTTPS
┌────────────────────────▼────────────────────────────────────┐
│  Azure App Service                                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Easy Auth (authV2)                                 │   │
│  │  • Validates Entra ID tokens                        │   │
│  │  • Injects X-MS-CLIENT-PRINCIPAL header             │   │
│  │  • Handles /.auth/login and /.auth/logout           │   │
│  └──────────────────────┬──────────────────────────────┘   │
│                         │                                   │
│  ┌──────────────────────▼──────────────────────────────┐   │
│  │  Flask app (Gunicorn)                               │   │
│  │  • Parses header → Principal (name, roles)          │   │
│  │  • @require_roles decorator gates each route        │   │
│  │  • Jinja2 templates render role-appropriate UI      │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│  Microsoft Entra ID                                         │
│  • App Registration with 3 App Roles                        │
│    (User, Premium, Admin)                                   │
│  • appRoleAssignmentRequired = true                         │
└─────────────────────────────────────────────────────────────┘
```

## Role Access Matrix

| Page       | Anonymous | Regular (User) | Premium | Admin |
|------------|:---------:|:--------------:|:-------:|:-----:|
| `/`        | ✅        | ✅             | ✅      | ✅    |
| `/dashboard` | → login | ✅             | ✅      | ✅    |
| `/premium` | → login   | ❌ 403         | ✅      | ✅    |
| `/admin`   | → login   | ❌ 403         | ❌ 403  | ✅    |

Signed-in users with **no role assigned** see a friendly 403 "Request Access" page.

## Project Structure

```
.
├── app/
│   ├── __init__.py          # Flask app factory
│   ├── auth.py              # Principal parsing, require_roles decorator
│   ├── routes.py            # View functions
│   ├── static/
│   │   ├── css/styles.css   # Single elegant stylesheet
│   │   └── js/
│   │       ├── app.js       # Global JS (active nav, ripple, year)
│   │       └── admin.js     # Admin dashboard chart + mock data
│   └── templates/
│       ├── base.html        # Role-aware nav + layout
│       ├── landing.html     # Public landing page
│       ├── dashboard.html   # Any authenticated role
│       ├── premium.html     # Premium + Admin
│       ├── admin.html       # Admin only
│       ├── 403.html         # Access denied
│       └── 404.html         # Not found
├── infra/
│   ├── main.bicep           # App Service Plan + Web App + Easy Auth v2
│   └── main.parameters.json # Parameter template (fill in or use local)
├── scripts/
│   ├── setup-app-registration.sh  # Creates App Reg + App Roles + secret
│   ├── assign-roles.sh            # Assigns a user to a role
│   └── deploy.sh                  # Deploys Bicep + app code
├── requirements.txt
├── gunicorn.conf.py
└── README.md
```

## Prerequisites

- Azure subscription
- `az` CLI ≥ 2.58 — [install](https://docs.microsoft.com/cli/azure/install-azure-cli)
- `jq` — `brew install jq` (macOS) or `apt install jq`
- Python 3.11+ (local smoke testing only)

```bash
az login
az account set --subscription <YOUR_SUBSCRIPTION_ID>
```

## One-Time Setup

### 1. Create the App Registration & App Roles

```bash
./scripts/setup-app-registration.sh \
  --app-name easyauth-demo \
  --app-service-hostname easyauth-demo.azurewebsites.net
```

This script:
- Creates the App Registration with the correct redirect URI
- Adds three App Roles (`User`, `Premium`, `Admin`)
- Sets `requestedAccessTokenVersion = 2`
- Creates a client secret (2-year expiry)
- Creates the enterprise app (service principal)
- Sets `appRoleAssignmentRequired = true` so only assigned users can sign in
- Writes `infra/main.parameters.local.json` (**gitignored — contains the secret**)

### 2. Deploy to Azure

```bash
./scripts/deploy.sh --resource-group easyauth-demo-rg --location westus2
```

This creates the resource group, runs `az deployment group create` with the Bicep template, then zips and deploys the app code.

### 3. Assign Roles to Demo Users

Use your real Entra ID user UPNs. Run one command per persona:

```bash
APP_ID=$(jq -r '.parameters.aadClientId.value' infra/main.parameters.local.json)

# Regular user
./scripts/assign-roles.sh --app-id "$APP_ID" --upn regular@yourdomain.com --role User

# Premium user
./scripts/assign-roles.sh --app-id "$APP_ID" --upn premium@yourdomain.com --role Premium

# Admin
./scripts/assign-roles.sh --app-id "$APP_ID" --upn admin@yourdomain.com --role Admin
```

The fourth persona — **anonymous** — requires no setup; just open the app without signing in.

## How It Works (Technical Detail)

### Easy Auth header

When a user signs in, Easy Auth validates their Entra ID token and injects:

```
X-MS-CLIENT-PRINCIPAL: <base64-encoded JSON>
```

The JSON looks like:

```json
{
  "auth_typ": "aad",
  "claims": [
    { "typ": "name",  "val": "Alice Nguyen" },
    { "typ": "roles", "val": "Admin" },
    { "typ": "oid",   "val": "00000000-0000-0000-0000-000000000000" }
  ]
}
```

**Security note:** App Service automatically strips any inbound `X-MS-CLIENT-PRINCIPAL` header supplied by external callers. The header is only present if set by Easy Auth itself — safe to trust.

### Flask auth.py

`get_principal()` decodes the base64 JSON and returns a `Principal` dataclass with `name`, `email`, `object_id`, `roles`, and `is_authenticated`. It attaches to `g.principal` via a `before_request` hook and is available in every Jinja2 template.

The `@require_roles("Admin")` decorator on a route:
1. Checks `g.principal.is_anonymous()` → redirects to `/.auth/login/aad?post_login_redirect_uri=<path>`
2. Checks `g.principal.has_role("Admin")` → renders `403.html` if missing
3. Otherwise calls the view function normally

## Local Smoke Testing

Without Easy Auth running locally, the app treats every request as anonymous:

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
flask --app "app:create_app()" run
```

Inject a fake header to test role gating:

```bash
# Encode a principal for a Premium user
PRINCIPAL=$(echo '{"auth_typ":"aad","claims":[{"typ":"name","val":"Test User"},{"typ":"roles","val":"Premium"},{"typ":"preferred_username","val":"test@contoso.com"}]}' | base64)

curl -H "X-MS-CLIENT-PRINCIPAL: $PRINCIPAL" http://localhost:5000/premium
# → 200 (Premium page)

curl -H "X-MS-CLIENT-PRINCIPAL: $PRINCIPAL" http://localhost:5000/admin
# → 403 (Access Denied)
```

**Note:** On real App Service, injecting this header externally will not work — App Service strips it. The above is for local testing only.

## Bicep What-If (Preview Changes)

```bash
az deployment group what-if \
  --resource-group easyauth-demo-rg \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.local.json
```

## Security Notes

| Topic | Detail |
|-------|--------|
| **Header trust** | App Service strips inbound `X-MS-CLIENT-PRINCIPAL`; safe to trust without additional verification |
| **HTTPS only** | `httpsOnly: true` + `minTlsVersion: 1.2` enforced in Bicep |
| **FTP disabled** | `ftpsState: Disabled` |
| **Client secret** | Stored as an app setting (plain). For production, use a [Key Vault reference](https://learn.microsoft.com/azure/app-service/app-service-key-vault-references): `@Microsoft.KeyVault(SecretUri=...)` |
| **Role assignment required** | `appRoleAssignmentRequired: true` — users not assigned any role cannot obtain a token for this app |
| **Token store** | Easy Auth token store enabled; tokens are server-side only |

## Teardown

```bash
az group delete --name easyauth-demo-rg --yes --no-wait
az ad app delete --id $(jq -r '.parameters.aadClientId.value' infra/main.parameters.local.json)
```

## Further Reading

- [App Service Authentication overview](https://learn.microsoft.com/azure/app-service/overview-authentication-authorization)
- [Configure Microsoft Entra authentication](https://learn.microsoft.com/azure/app-service/configure-authentication-provider-aad)
- [Work with user identities in Easy Auth](https://learn.microsoft.com/azure/app-service/configure-authentication-user-identities)
- [App roles in Microsoft Entra](https://learn.microsoft.com/azure/active-directory/develop/howto-add-app-roles-in-apps)
