FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
	build-essential clang flex bison g++ gawk \
	gcc-multilib g++-multilib gettext git libncurses-dev libssl-dev \
	python3 python3-dev python3-setuptools rsync swig unzip \
	zlib1g-dev file wget curl ca-certificates xz-utils zstd \
	libelf-dev quilt \
	&& rm -rf /var/lib/apt/lists/*

# OpenWrt refuses to build as root
RUN useradd -m -s /bin/bash build
USER build
WORKDIR /home/build

CMD ["bash"]
