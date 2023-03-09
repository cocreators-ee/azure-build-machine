FROM ghcr.io/lietu/ubuntu-base:22.04

# Generic global flags for predictability
ENV GOPATH="$HOME/go" \
    PATH="/root/.local/bin:/usr/lib/go-1.20/bin:$GOHOME/bin:$PATH"

ADD setup_docker.sh lib.sh prepare.sh /
RUN bash /setup_docker.sh

ADD docker_entrypoint.sh /
ENTRYPOINT ["bash", "/docker_entrypoint.sh"]
