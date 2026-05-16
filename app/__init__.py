from flask import Flask
from .auth import init_auth
from . import routes


def create_app():
    app = Flask(__name__)

    # Register auth hooks and context processor
    init_auth(app)

    # Register routes
    app.register_blueprint(routes.bp)

    # Custom error handlers
    @app.errorhandler(404)
    def not_found(e):
        from flask import render_template
        return render_template("404.html"), 404

    @app.errorhandler(403)
    def forbidden(e):
        from flask import render_template
        return render_template("403.html"), 403

    return app
