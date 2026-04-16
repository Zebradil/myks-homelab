FROM caddy:2.11.2-alpine@sha256:24d58e24e4231c6667677a39469a3d843a3222eadbf640f22933f24bed0939ec

# Copy assets to the web root
COPY assets/Caddyfile /etc/caddy/Caddyfile
COPY assets/index.html /srv/index.html
COPY assets/manifest.json /srv/manifest.json
COPY assets/icon-192.png /srv/icon-192.png
COPY assets/icon-512.png /srv/icon-512.png

# Run as non-root user
USER 1001
