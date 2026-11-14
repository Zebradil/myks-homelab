FROM --platform=linux/amd64 caddy:2.11.8-alpine@sha256:f6228111e5fafa1a5238258d0858e103f10599b8d1659a146e7726681a002bb9

# The Caddyfile is not baked in: it carries a reverse_proxy route per camera and
# comes from the ConfigMap generated in ytt/cameras.ytt.yaml.
COPY assets/index.html /srv/index.html
COPY assets/style.css /srv/style.css
COPY assets/app.js /srv/app.js
COPY assets/manifest.json /srv/manifest.json
COPY assets/icon-192.png /srv/icon-192.png
COPY assets/icon-512.png /srv/icon-512.png

# Run as non-root user
USER 1001
