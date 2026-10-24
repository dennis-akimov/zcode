# syntax=docker/dockerfile:1.7
# ZCode desktop (Electron) in a container, shown in the browser via noVNC.
FROM debian:bookworm-slim

ARG TARGETARCH
ARG ZCODE_VERSION=3.16.3
ARG ZCODE_SHA256_AMD64=128132b195977fd0a8c8a6c295cf42fe159222d7a5c5efefd8b5f00ef88ab8b6
ARG ZCODE_SHA256_ARM64=338e91013125ee49f665f1dc3a07af09518b05f53f9a5a359de4572009c660e2

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git openssh-client \
      tigervnc-standalone-server tigervnc-tools novnc websockify openbox \
      dbus desktop-file-utils fonts-dejavu-core fonts-noto-cjk \
      libgbm1 libasound2 `# the deb links these but does not declare them` \
    && rm -rf /var/lib/apt/lists/*

# The CDN publishes no checksums; these were taken from the 3.16.3 debs. Bump all three together.
RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) arch=x64;   sum="$ZCODE_SHA256_AMD64" ;; \
      arm64) arch=arm64; sum="$ZCODE_SHA256_ARM64" ;; \
      *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/zcode.deb \
      "https://cdn-zcode.z.ai/zcode/electron/releases/${ZCODE_VERSION}/linux-${arch}/ZCode-${ZCODE_VERSION}-linux-${arch}.deb"; \
    echo "$sum  /tmp/zcode.deb" | sha256sum -c -; \
    apt-get update; apt-get install -y --no-install-recommends /tmp/zcode.deb; \
    rm -rf /tmp/zcode.deb /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash zcode && mkdir -p /home/zcode/work && chown zcode:zcode /home/zcode/work \
    && mkdir -m 1777 /tmp/.X11-unix   # Xvnc wants it root-owned; as non-root it can't create it

# Agent toolchain: Node + npm/npx, FFmpeg, Playwright Chromium (the motion-reel skill needs all three).
# Node goes to /usr/local, which precedes /usr/bin on PATH and so shadows Debian's Node 18 (pulled in by novnc).
ARG NODE_VERSION=24.22.1
ARG NODE_SHA256_AMD64=6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6
ARG NODE_SHA256_ARM64=dbabf7a1cbf947e6059ffad2c27b80041db97dea1e553b62afdee7f13fca336e
ARG PLAYWRIGHT_VERSION=1.58.2
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) arch=x64;   sum="$NODE_SHA256_AMD64" ;; \
      arm64) arch=arm64; sum="$NODE_SHA256_ARM64" ;; \
    esac; \
    apt-get update; apt-get install -y --no-install-recommends ffmpeg xz-utils; \
    curl -fsSL -o /tmp/node.tar.xz \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${arch}.tar.xz"; \
    echo "$sum  /tmp/node.tar.xz" | sha256sum -c -; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner \
      --exclude='*/CHANGELOG.md' --exclude='*/LICENSE' --exclude='*/README.md'; \
    npm install -g --no-fund --no-audit "playwright@${PLAYWRIGHT_VERSION}"; \
    playwright install --with-deps chromium; \
    chown -R zcode:zcode "$PLAYWRIGHT_BROWSERS_PATH"; \
    rm -rf /tmp/node.tar.xz /var/lib/apt/lists/* /root/.npm

# One bus at a fixed path so `docker exec` shells reach the same session as the app.
# ponytail: the system bus points at it too; Chromium only asks it for UPower/logind, which a
# container doesn't have, and gets a quiet "no owner" instead of a connect error. A real
# system bus would need a root daemon.
ENV DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/dbus-session \
    DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbus-session \
    NODE_NO_WARNINGS=1

# Shadows /usr/bin/zcode so `docker exec ... zcode` gets the same flags as the session;
# a second launch just hands off to the running window (single instance).
# ponytail: --no-sandbox because Docker's seccomp blocks Chromium's namespace sandbox (and
# no-new-privileges blocks the setuid one); the container is the sandbox.
COPY --chmod=755 <<'EOF' /usr/local/bin/zcode
#!/bin/sh
exec /opt/ZCode/zcode --no-sandbox --disable-gpu "$@"
EOF
ENV DISPLAY=:1

COPY --chmod=755 <<'EOF' /usr/local/bin/start-zcode
#!/bin/sh
set -eu
: "${VNC_PASSWORD:?set VNC_PASSWORD in .env}"
# RFC 6143 7.2.2: VNC auth keys DES with the first 8 chars only; the rest are ignored.
[ "${#VNC_PASSWORD}" -ge 8 ] || { echo "VNC_PASSWORD must be at least 8 chars" >&2; exit 1; }
mkdir -p ~/.vnc
printf '%s\n' "$VNC_PASSWORD" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 /tmp/dbus-session   # stale after `docker restart`
# Chromiums profile lock names the old hostname after `make upgrade` and would refuse to start.
rm -f ~/.config/ZCode/Singleton*
dbus-daemon --session --address="$DBUS_SESSION_BUS_ADDRESS" --fork --nopidfile

# Xvnc listens on the container's loopback only; noVNC is the one way in.
Xvnc :1 -geometry "${GEOMETRY:-1600x1000}" -depth 24 -localhost -rfbport 5901 \
     -rfbauth ~/.vnc/passwd -SecurityTypes VncAuth -AlwaysShared &
i=0; until [ -S /tmp/.X11-unix/X1 ]; do   # openbox/zcode exit if the display isn't up yet
  i=$((i+1)); [ "$i" -le 100 ] || { echo "Xvnc did not start" >&2; exit 1; }; sleep 0.1
done
websockify --web /usr/share/novnc 6080 127.0.0.1:5901 &
openbox &

cd ~/work
exec zcode
EOF

USER zcode
WORKDIR /home/zcode/work
EXPOSE 6080
CMD ["start-zcode"]
