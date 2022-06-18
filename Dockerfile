FROM ubuntu:20.04

# Generic global flags for predictability
ENV LC_ALL="C.UTF-8" \
    LANG="C.UTF-8" \
    DEBIAN_FRONTEND="noninteractive" \
    TZ="UTC" \
    GOPATH="$HOME/go" \
    PATH="/root/.local/bin:/usr/lib/go-1.18/bin:$GOHOME/bin:$PATH"

ADD setup_docker.sh /
RUN bash /setup_docker.sh

ADD docker_entrypoint.sh /
ENTRYPOINT ["bash", "/docker_entrypoint.sh"]
