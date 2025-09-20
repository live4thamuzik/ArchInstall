# Multi-stage Dockerfile for ArchInstall development and testing

# Build stage
FROM rust:1.75-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy source code
COPY . .

# Build the application
RUN cargo build --release

# Runtime stage
FROM archlinux:latest

# Install runtime dependencies
RUN pacman -Syu --noconfirm \
    && pacman -S --noconfirm \
        bash \
        git \
        arch-install-scripts \
        parted \
        gdisk \
        lvm2 \
        mdadm \
        cryptsetup \
        grub \
        networkmanager \
        systemd \
    && pacman -Scc --noconfirm

# Copy binary from builder stage
COPY --from=builder /app/target/release/archinstall-tui /usr/local/bin/
COPY --from=builder /app/*.sh /usr/local/bin/

# Set permissions
RUN chmod +x /usr/local/bin/*.sh

# Set working directory
WORKDIR /app

# Expose port for potential web interface
EXPOSE 8080

# Default command
CMD ["/usr/local/bin/archinstall-tui"]