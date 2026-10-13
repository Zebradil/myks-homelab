FROM --platform=linux/amd64 caddy:2.11.7-alpine@sha256:d8542f48d34a9cf4e4c11a478865229840e87e4c96ea3f439101f31a5d35f75f

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
