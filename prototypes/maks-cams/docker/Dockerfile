FROM --platform=linux/amd64 caddy:2.11.3-alpine@sha256:86deaf5e3d3408a6ccec08fbb79989783dd26e206ae10bcf78a801dc8c9ab794

# Copy assets to the web root
COPY assets/Caddyfile /etc/caddy/Caddyfile
COPY assets/index.html /srv/index.html
COPY assets/style.css /srv/style.css
COPY assets/app.js /srv/app.js
COPY assets/manifest.json /srv/manifest.json
COPY assets/icon-192.png /srv/icon-192.png
COPY assets/icon-512.png /srv/icon-512.png

# Run as non-root user
USER 1001
