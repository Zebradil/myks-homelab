FROM caddy:2.11.1-alpine@sha256:3b2a0196e0687279c14c27adff9fc6b44acfa318dbb97eaebe385bdf99e5364c

# Copy assets to the web root
COPY assets/Caddyfile /etc/caddy/Caddyfile
COPY assets/index.html /srv/index.html
COPY assets/manifest.json /srv/manifest.json
COPY assets/icon-192.png /srv/icon-192.png
COPY assets/icon-512.png /srv/icon-512.png

# Run as non-root user
USER 1001
