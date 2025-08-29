FROM rust:1.75-alpine
RUN apk add --no-cache musl-dev
WORKDIR /app
COPY Cargo.toml .
COPY src ./src
RUN cargo build --release
EXPOSE 3000
CMD ["./target/release/rust-backend"]
