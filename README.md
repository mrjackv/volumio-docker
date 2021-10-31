## Volumio Docker Image

This is a docker image for [volumio](https://volumio.com/),
reworked from [here](https://github.com/jbonjean/docker-public/tree/master/volumio)

To run:
```
docker build -t volumio .
./run.sh
```

## Changes from jbonjean version

* Supports multiarch (386, x86_64, arm, arm64)
* Uses debian bullseye as base image (since ubuntu doesn't have the 386 variant)
* Completely standalone, starts from scratch with the debian image
* Pulse audio forwarding reworked
* `run.sh` script, to easily start everything

## TODO

* transform `run.sh` in docker-compose
