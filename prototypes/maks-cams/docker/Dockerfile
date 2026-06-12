FROM --platform=linux/amd64 caddy:2.11.4-alpine@sha256:77c07d5ebfa5be9fd6c820d2094ae662c9e7eeb9bf98346b7f639900263ee2a2

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
