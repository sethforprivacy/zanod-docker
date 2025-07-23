# Build Zano
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Set Zano branch and commit to build against
ARG ZANO_BRANCH=2.1.7.418
ARG ZANO_COMMIT=f8e298af8638b63a18e39d86f1a585cacba3644e

# Download and install dependencies
RUN apt update && \
    apt install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    g++ \
    gcc \
    git \
    libicu-dev \
    libssl-dev \
    libz-dev \
    pkg-config \
    && apt clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /root

# Boost library Settings
ARG BOOST_VERSION=1_84_0
ARG BOOST_VERSION_DOT=1.84.0
ARG BOOST_HASH=cc4b893acf645c9d4b698e9a0f08ca8846aa5d6c68275c14c3e7949c24109454

# Number of threads to use when building
# Set to 4 by default, simply remove the =4 to enable automatic thread detection
# Note that automatically detecting threads can often lead to a failure to build due to lack of memory
ARG NPROC

# Environment Variables
ENV BOOST_ROOT=/root/boost_${BOOST_VERSION}
ENV OPENSSL_ROOT_DIR=/root/openssl

# Download Boost
RUN set -ex \
    && curl -L -o  boost_${BOOST_VERSION}.tar.bz2 https://downloads.sourceforge.net/project/boost/boost/${BOOST_VERSION_DOT}/boost_${BOOST_VERSION}.tar.bz2 \
    && sha256sum boost_${BOOST_VERSION}.tar.bz2 \
    && echo "${BOOST_HASH}  boost_${BOOST_VERSION}.tar.bz2" | sha256sum -c\
    && tar -xvf boost_${BOOST_VERSION}.tar.bz2

# Compile Boost
RUN set -ex \
    && cd boost_${BOOST_VERSION} \
    && ./bootstrap.sh --with-libraries=system,filesystem,thread,date_time,chrono,regex,serialization,atomic,program_options,locale,timer,log \
    && ./b2 -j ${NPROC:-$(nproc)}

# Build zanod daemon from chosen branch/release
RUN set -x &&\
    git clone --single-branch --recursive --branch ${ZANO_BRANCH} https://github.com/hyle-team/zano.git &&\
    cd zano &&\
    test `git rev-parse HEAD` = ${ZANO_COMMIT} || exit 1 &&\
    mkdir build && cd build &&\
    cmake -D STATIC=TRUE .. &&\
    make -j ${NPROC:-$(nproc)} daemon

# Run Zano in final image
FROM ubuntu:24.04 AS final

# Upgrade base image
RUN apt update \
    && apt upgrade -y

# Install dependencies
RUN apt update && apt install --no-install-recommends -y \
    curl \
    && apt clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create non-root zano user and group
RUN useradd -ms /bin/bash zano \
    && mkdir -p /home/zano/.Zano \
    && chown -R zano:zano /home/zano/.Zano

USER zano:zano

WORKDIR /home/zano

# Copy zanod binary from build stage
COPY --chown=zano:zano --from=builder /root/zano/build/src/zanod /usr/local/bin/zanod

# Set blockchain location
VOLUME /home/zano/.Zano/

# Expose p2p and RPC ports, respectively
EXPOSE 11121 11211

# Add HEALTHCHECK against get_info endpoint
HEALTHCHECK --interval=30s --timeout=5s CMD curl --fail http://localhost:11211/getinfo || exit 1

# Always start zanod
ENTRYPOINT ["zanod"]

# Start zanod with sane defaults
CMD ["--disable-upnp", "--log-level=0", "--no-console", "--rpc-bind-ip=0.0.0.0"]
