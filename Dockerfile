FROM ubuntu:24.04
LABEL maintainer="aKernel <software.ckm@gmail.com>"
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    jq \
    transmission-cli \
    git \
    python3 \
    figlet \
    bc \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sL https://raw.githubusercontent.com/aKernel-soft/storm-central/main/install.sh | bash

ENTRYPOINT ["stoler"]
CMD ["shop"]
