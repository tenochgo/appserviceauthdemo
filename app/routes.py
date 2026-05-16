from flask import Blueprint, render_template, redirect, url_for, g
from .auth import require_roles, ROLE_REGULAR, ROLE_PREMIUM, ROLE_ADMIN

bp = Blueprint("main", __name__)


@bp.route("/")
def landing():
    return render_template("landing.html")


@bp.route("/dashboard")
@require_roles(ROLE_REGULAR, ROLE_PREMIUM, ROLE_ADMIN)
def dashboard():
    return render_template("dashboard.html")


@bp.route("/premium")
@require_roles(ROLE_PREMIUM, ROLE_ADMIN)
def premium():
    return render_template("premium.html")


@bp.route("/admin")
@require_roles(ROLE_ADMIN)
def admin():
    return render_template("admin.html")


@bp.route("/logout")
def logout():
    return redirect("/.auth/logout?post_logout_redirect_uri=/")


@bp.route("/healthz")
def healthz():
    return "OK", 200
