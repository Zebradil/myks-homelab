FROM caddy:2.10.2-alpine

# Copy assets to the web root
COPY assets/Caddyfile /etc/caddy/Caddyfile
COPY assets/index.html /srv/index.html
COPY assets/manifest.json /srv/manifest.json
COPY assets/icon-192.png /srv/icon-192.png
COPY assets/icon-512.png /srv/icon-512.png

# Run as non-root user
USER 1001
