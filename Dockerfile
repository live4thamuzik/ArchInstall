# Multi-stage Dockerfile for archinstall-tui
# Stage 1: Build environment
FROM rust:1.75-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Cargo files first for better caching
COPY Cargo.toml Cargo.lock ./

# Copy source code
COPY src/ ./src/

# Build the application
RUN cargo build --release

# Stage 2: Runtime environment
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    bash \
    util-linux \
    parted \
    e2fsprogs \
    btrfs-progs \
    xfsprogs \
    f2fs-tools \
    nilfs-utils \
    dosfstools \
    arch-install-scripts \
    git \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash archinstall && \
    usermod -aG disk archinstall

# Set working directory
WORKDIR /app

# Copy built binary from builder stage
COPY --from=builder /app/target/release/archinstall-tui /usr/local/bin/

# Copy configuration and scripts
COPY config.yaml /etc/archinstall/
COPY *.sh /usr/local/share/archinstall/
COPY Source/ /usr/local/share/archinstall/Source/
COPY README.md LICENSE /usr/local/share/archinstall/

# Create necessary directories
RUN mkdir -p /mnt /var/log/archinstall

# Set permissions
RUN chmod +x /usr/local/bin/archinstall-tui && \
    chmod +x /usr/local/share/archinstall/*.sh && \
    chown -R archinstall:archinstall /usr/local/share/archinstall

# Switch to non-root user
USER archinstall

# Set environment variables
ENV PATH="/usr/local/bin:${PATH}"
ENV ARCHINSTALL_CONFIG="/etc/archinstall/config.yaml"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD archinstall-tui --version || exit 1

# Default command
ENTRYPOINT ["archinstall-tui"]
CMD ["--help"]

# Labels
LABEL maintainer="archinstall-tui team"
LABEL description="Advanced Arch Linux installer with TUI"
LABEL version="1.0.0"
LABEL org.opencontainers.image.source="https://github.com/user/archinstall"
LABEL org.opencontainers.image.description="Advanced Arch Linux installer with TUI"
LABEL org.opencontainers.image.licenses="MIT"
