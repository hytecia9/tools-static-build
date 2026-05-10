ARG BASE_IMAGE=dockcross/linux-x64
FROM ${BASE_IMAGE}

ARG TOOL_NAME=nmap

ENV TOOL_NAME=${TOOL_NAME}

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    bison \
    bzip2 \
    ca-certificates \
    cmake \
    curl \
    file \
    flex \
    g++ \
    gawk \
    git \
    libtool \
    make \
    patch \
    perl \
    pkg-config \
    python3 \
    texinfo \
    unzip \
    xz-utils \
 && rm -rf /var/lib/apt/lists/*

COPY scripts /opt/tsb

RUN chmod +x /opt/tsb/entrypoint.sh /opt/tsb/tools/*.sh

ENTRYPOINT ["/opt/tsb/entrypoint.sh"]