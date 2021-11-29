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

ENV CORE_VERSION=65023745b40b190d7586775708defe2c207fba78
ENV CORE_SHA256=e4090fb579119341dc19fba8bf0eae4d33438c8b7c5c68d290c8039b4c669fc1

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

ENV UI_VERSION=a6f7de9f19757c53f1f52a89a3a75ea75528ba67
ENV UI_SHA256=a69a1351867048d42a987d87190b146a3e5a51933068b14ba11982a5c8fa8710

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

COPY scripts/entrypoint /entrypoint
COPY scripts/lscpu scripts/dpkg /usr/local/bin

ENTRYPOINT /entrypoint
