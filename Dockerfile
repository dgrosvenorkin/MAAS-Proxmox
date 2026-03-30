FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    qemu-system-x86 \
    qemu-utils \
    ovmf \
    cloud-image-utils \
    make \
    ansible \
    git \
    libnbd-bin \
    nbdkit \
    fuse2fs \
    fuse3 \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Install Packer with checksum verification
# SHA256SUMS sourced from: https://releases.hashicorp.com/packer/1.11.2/packer_1.11.2_SHA256SUMS
ARG PACKER_VERSION=1.11.2
RUN cd /tmp \
    && wget -O "packer_${PACKER_VERSION}_linux_amd64.zip" \
        "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" \
    && wget -O packer_SHA256SUMS \
        "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_SHA256SUMS" \
    && grep "packer_${PACKER_VERSION}_linux_amd64.zip" packer_SHA256SUMS | sha256sum -c \
    && unzip "packer_${PACKER_VERSION}_linux_amd64.zip" -d /usr/local/bin/ \
    && rm "packer_${PACKER_VERSION}_linux_amd64.zip" packer_SHA256SUMS \
    && chmod +x /usr/local/bin/packer

# Create build user (KVM group will be added at runtime by docker-compose)
RUN useradd -m -u 1000 builder \
    && mkdir -p /home/builder/.cache/packer \
    && chown -R builder:builder /home/builder/.cache

# Set working directory
WORKDIR /build

# Copy entrypoint script and make it executable
COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

USER builder

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
