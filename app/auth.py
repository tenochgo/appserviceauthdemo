"""
auth.py — Easy Auth principal parsing and role-based access control.

Azure App Service Easy Auth injects the `X-MS-CLIENT-PRINCIPAL` header on
every authenticated request. The header value is a base64-encoded JSON object
that contains the user's claims including any App Registration App Roles.

Security note: App Service automatically strips any inbound
`X-MS-CLIENT-PRINCIPAL` header supplied by external callers, so the header
can only have been set by the Easy Auth middleware — safe to trust on Azure.
When running locally (no Easy Auth), the header is absent and the user is
treated as anonymous.
"""

from __future__ import annotations

import base64
import json
from dataclasses import dataclass, field
from functools import wraps
from typing import Set

from flask import g, redirect, render_template, request

# ---------------------------------------------------------------------------
# Role constants — must match the "value" field of the App Roles defined in
# your App Registration manifest.
# ---------------------------------------------------------------------------
ROLE_REGULAR = "User"
ROLE_PREMIUM = "Premium"
ROLE_ADMIN = "Admin"

ALL_ROLES = {ROLE_REGULAR, ROLE_PREMIUM, ROLE_ADMIN}

# Role display metadata used in templates
ROLE_META = {
    ROLE_REGULAR: {"label": "Regular User", "color": "role-regular"},
    ROLE_PREMIUM: {"label": "Premium User", "color": "role-premium"},
    ROLE_ADMIN:   {"label": "Admin",        "color": "role-admin"},
}


@dataclass
class Principal:
    name: str = "Anonymous"
    email: str = ""
    object_id: str = ""
    roles: Set[str] = field(default_factory=set)
    is_authenticated: bool = False

    # ------------------------------------------------------------------
    # Convenience helpers
    # ------------------------------------------------------------------
    def is_anonymous(self) -> bool:
        return not self.is_authenticated

    def has_role(self, *roles: str) -> bool:
        """Return True if the principal holds ANY of the given roles."""
        return bool(self.roles & set(roles))

    def highest_role(self) -> str | None:
        """Return the most privileged assigned role label, for display."""
        for role in (ROLE_ADMIN, ROLE_PREMIUM, ROLE_REGULAR):
            if role in self.roles:
                return role
        return None

    def role_badges(self) -> list[dict]:
        """Return sorted list of role metadata dicts for badge rendering."""
        return [ROLE_META[r] for r in (ROLE_ADMIN, ROLE_PREMIUM, ROLE_REGULAR)
                if r in self.roles]


# ---------------------------------------------------------------------------
# Header parsing
# ---------------------------------------------------------------------------

def get_principal() -> Principal:
    """
    Decode the Easy Auth header and return a Principal.
    Returns an anonymous Principal if the header is absent or malformed.
    """
    header = request.headers.get("X-MS-CLIENT-PRINCIPAL")
    if not header:
        return Principal()

    try:
        # Pad base64 if needed
        padded = header + "=" * (-len(header) % 4)
        payload = json.loads(base64.b64decode(padded).decode("utf-8"))
    except Exception:
        return Principal()

    claims: dict[str, str] = {}
    for claim in payload.get("claims", []):
        typ = claim.get("typ", "")
        val = claim.get("val", "")
        claims.setdefault(typ, val)

    # Collect all role claims (there can be multiple)
    roles: set[str] = set()
    for claim in payload.get("claims", []):
        if claim.get("typ") == "roles":
            roles.add(claim.get("val", ""))

    name = (
        claims.get("name")
        or claims.get("preferred_username")
        or claims.get("http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name")
        or "User"
    )
    email = (
        claims.get("preferred_username")
        or claims.get("email")
        or claims.get("http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress")
        or ""
    )
    oid = (
        claims.get("oid")
        or claims.get("http://schemas.microsoft.com/identity/claims/objectidentifier")
        or ""
    )

    return Principal(
        name=name,
        email=email,
        object_id=oid,
        roles=roles,
        is_authenticated=True,
    )


# ---------------------------------------------------------------------------
# Flask integration
# ---------------------------------------------------------------------------

def init_auth(app):
    """Register before_request hook and context processor with the Flask app."""

    @app.before_request
    def _attach_principal():
        g.principal = get_principal()

    @app.context_processor
    def _inject_principal():
        return {
            "principal": g.get("principal", Principal()),
            "ROLE_REGULAR": ROLE_REGULAR,
            "ROLE_PREMIUM": ROLE_PREMIUM,
            "ROLE_ADMIN": ROLE_ADMIN,
        }


# ---------------------------------------------------------------------------
# Decorator
# ---------------------------------------------------------------------------

def require_roles(*roles: str):
    """
    View decorator that gates access by role.

    - Anonymous  → redirect to Easy Auth login
    - Authenticated but no matching role → render 403 (request access)
    - Matching role → call the view normally
    """
    def decorator(f):
        @wraps(f)
        def wrapped(*args, **kwargs):
            principal: Principal = g.get("principal", Principal())
            if principal.is_anonymous():
                login_url = (
                    f"/.auth/login/aad"
                    f"?post_login_redirect_uri={request.path}"
                )
                return redirect(login_url)
            if not principal.has_role(*roles):
                return render_template("403.html"), 403
            return f(*args, **kwargs)
        return wrapped
    return decorator
