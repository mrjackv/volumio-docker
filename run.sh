#!/bin/sh

sudo docker run --restart=always -d --name volumio \
                -e HOST=http://127.0.0.1:3000 \
                -p 3000:3000 \
                -v volumio-data:/data \
                -v /run/user/$(id -u)/pulse:/pulse:ro \
                -v "${HOME}/.config/pulse/cookie:/pulse-cookie" \
                -e PULSE_COOKIE=/pulse-cookie \
                -e PULSE_SERVER=unix:/pulse/native \
                -e HOST_USER=$(id -u):$(id -g) \
                -e AUDIO_OUTPUT=pulse \
                volumio
#-v ${MUSIC_DIR}:/var/lib/mpd/music/:ro \
