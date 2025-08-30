FROM rust:1.79-bookworm AS builder

RUN apt-get update && apt-get install -y \
    cmake \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Cargo.toml ./
COPY src ./src
RUN cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    postgresql-client \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install MinIO client
RUN wget https://dl.min.io/client/mc/release/linux-amd64/mc \
    && chmod +x mc \
    && mv mc /usr/local/bin/

WORKDIR /app
COPY --from=builder /app/target/release/rust-backend /app/rust-backend
EXPOSE 3000
CMD ["./rust-backend"]
