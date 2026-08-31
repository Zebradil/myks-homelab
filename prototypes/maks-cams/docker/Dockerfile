FROM --platform=linux/amd64 caddy:2.11.4-alpine@sha256:5f5c8640aae01df9654968d946d8f1a56c497f1dd5c5cda4cf95ab7c14d58648

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
