# Cross toolchain for MiSTer (ARMv7 hard-float, glibc 2.31 == Debian bullseye)
FROM debian:bullseye
RUN rm -f /etc/apt/sources.list.d/* \
    && printf 'deb http://archive.debian.org/debian bullseye main\n' > /etc/apt/sources.list \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gcc-arm-linux-gnueabihf libc6-dev-armhf-cross binutils-arm-linux-gnueabihf make curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://github.com/Kitware/CMake/releases/download/v3.31.6/cmake-3.31.6-linux-x86_64.tar.gz \
    | tar -xz -C /opt && ln -s /opt/cmake-3.31.6-linux-x86_64/bin/* /usr/local/bin/
WORKDIR /src
