# Env var (and sops key) holding an app's private key.
def pem_env(app):
    return app.name.upper().replace("-", "_") + "_PEM"
end
