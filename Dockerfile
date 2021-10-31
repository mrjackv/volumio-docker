FROM docker.io/library/debian:bullseye as base

ADD scripts/cleanup /usr/bin

RUN apt update && \
    apt install -y --no-install-recommends curl ca-certificates xz-utils && \
    cleanup

ENV NODE_VERSION="8.17.0"

ADD scripts/install-node /tmp

RUN /tmp/install-node

ENV PATH=/opt/node/bin:$PATH



FROM base as builder

RUN apt update && \
    apt install -y --no-install-recommends \
                build-essential \
                libavahi-compat-libdnssd-dev \
                libudev-dev python git


# Build Volumio Core.
FROM builder as core-builder

ENV CORE_VERSION=307f91893fca011201acba9973e1c41bd3a0ad5d
ENV CORE_SHA256=22a4f9d1c5fb4f76c8535f12664c8bd6d49189fb603ceabf2581392673723041

RUN curl -Lo /tmp/volumio.tar.gz "https://github.com/volumio/Volumio2/archive/$CORE_VERSION.tar.gz" && \
    sha256sum /tmp/volumio.tar.gz && \
    echo "$CORE_SHA256 /tmp/volumio.tar.gz" | sha256sum --check --status && \
    mkdir -p /dist/volumio && \
    tar -C /dist/volumio --strip-components=1 -xf /tmp/volumio.tar.gz && \
    rm -f /tmp/volumio.tar.gz

# Remove fs-extra package that seems to cause issue on runtime. TBD.
RUN sed -i '/"fs-extra"/d' /dist/volumio/package.json

RUN cd /dist/volumio && \
    npm install --production && \
    node /dist/volumio/utils/misc/clean-node-modules.js /dist/volumio



# Build Volumio UI.
FROM builder as ui-builder

ENV UI_VERSION=0447a58df1fcd398ffda4f42c5fd09900a32ee0c
ENV UI_SHA256=c04d26950acead5d42e9854df5a1ce0990f0646368cf29f6f2b5a1baefa3fc2d

RUN curl -Lo /tmp/volumio-ui.tar.gz "https://github.com/volumio/Volumio2-UI/archive/$UI_VERSION.tar.gz" && \
    sha256sum /tmp/volumio-ui.tar.gz && \
    echo "$UI_SHA256 /tmp/volumio-ui.tar.gz" | sha256sum --check --status && \
    mkdir -p /tmp/volumio-ui && \
    tar -C /tmp/volumio-ui --strip-components=1 -xf /tmp/volumio-ui.tar.gz && \
    rm -f /tmp/volumio-ui.tar.gz

ADD credits.js.diff /tmp
ADD scripts/fake-phantomjs /usr/bin/phantomjs

RUN cd /tmp/volumio-ui/src/app/themes/volumio/scripts && \
    patch -p1 < /tmp/credits.js.diff && \
    cd /tmp/volumio-ui && \
    npm install && \
    npm install -g bower gulp && \
    bower install --allow-root && \
    gulp build --theme="volumio" --env="production" && \
    mkdir -p /dist && mv /tmp/volumio-ui/dist /dist/volumio



# Build final image.
FROM base as final

RUN apt update && \
    apt install -y --no-install-recommends \
                alsa-utils avahi-daemon avahi-utils \
                libavahi-compat-libdnssd1 libnss-mdns \
                minizip mpc mpd pulseaudio shairport-sync \
                sudo wget s6 gosu jq tini \
    && cleanup

# Add specific user and group (hardcoded).
RUN groupadd -g 1000 volumio && useradd -u 1000 -g 1000 volumio && \
    # add users to audio group
    usermod -a -G audio volumio && usermod -a -G audio mpd

# Install dist from previous stages.
COPY --from=core-builder /dist/volumio /volumio
COPY --from=ui-builder /dist/volumio /volumio/http/www

# Symlink library to /mnt for volumio.
RUN rm -rf /mnt && ln -s /var/lib/mpd/music /mnt && \
    # Create node symlink in /usr/local (hardcoded).
    ln -s /opt/node/bin/node /usr/local/bin/node

# Copy services and config.
COPY etc /etc

# A few additional hacks to finalize the image.
COPY scripts/volumio-image-hacks /tmp/
RUN /tmp/volumio-image-hacks

ADD scripts/entrypoint /entrypoint
ENTRYPOINT /entrypoint
