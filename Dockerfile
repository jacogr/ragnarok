# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# Build the checked ThinLTO peer with Make; keep its toolchains available as the builder target.
# Official image digests pin the bootstrap environments; application toolchain pins remain in spec/.
FROM rust:1.99.0-slim-bookworm@sha256:2c3a22f0a5533ea2dd5a16627bc841228151faa2d4de2644ac9987e4a2f1f2fa AS rust-toolchain
FROM ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac AS builder

# Nimony currently ships a Linux x86-64 toolchain only; fail before provisioning another architecture.
ARG TARGETARCH
RUN test "$TARGETARCH" = amd64
RUN apt-get update && apt-get install --no-install-recommends -y \
    build-essential ca-certificates clang cmake git lld make openssl python3 xz-utils zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
COPY --from=rust-toolchain /usr/local/cargo /usr/local/cargo
COPY --from=rust-toolchain /usr/local/rustup /usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    PATH=/usr/local/cargo/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UI_MINIFY=1
WORKDIR /src
# Retain only source Git objects/index/refs; Make initializes pristine pinned submodules itself.
COPY . .
RUN git rev-parse --verify HEAD && make build
# C ABI libraries have absolute DT_NEEDED entries; package names and a binary-relative runpath.
RUN apt-get update && apt-get install --no-install-recommends -y patchelf \
    && mkdir /out && cp /src/build/ragnarok /out/ragnarok \
    && patchelf \
      --replace-needed /src/build/crypto/libragnarok_crypto.so libragnarok_crypto.so \
      --replace-needed /src/build/bandersnatch/target/release/libragnarok_bandersnatch.so libragnarok_bandersnatch.so \
      --replace-needed /src/build/quic/libquic_proof.so libquic_proof.so \
      --set-rpath '$ORIGIN/../lib/ragnarok' /out/ragnarok \
    && rm -rf /var/lib/apt/lists/*

# Ship only the peer, its maintained native ABIs and the required system runtime libraries.
FROM ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac AS runtime
RUN apt-get update && apt-get install --no-install-recommends -y \
    ca-certificates libgcc-s1 libstdc++6 zlib1g \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 ragnarok \
    && useradd --uid 10001 --gid 10001 --home-dir /data --no-create-home ragnarok \
    && mkdir /data && chown 10001:10001 /data
COPY LICENSE-APACHE LICENSE-MIT /usr/share/doc/ragnarok/
COPY --from=builder /out/ragnarok /usr/local/bin/ragnarok
COPY --from=builder /src/build/crypto/libragnarok_crypto.so /usr/local/lib/ragnarok/
COPY --from=builder /src/build/bandersnatch/target/release/libragnarok_bandersnatch.so /usr/local/lib/ragnarok/
COPY --from=builder /src/build/quic/libquic_proof.so /usr/local/lib/ragnarok/
LABEL org.opencontainers.image.source="https://github.com/jacogr/ragnarok" \
    org.opencontainers.image.licenses="MIT OR Apache-2.0"
WORKDIR /data
USER 10001:10001
# Check shared-library resolution in the final image under the actual runtime user.
RUN ["/usr/local/bin/ragnarok", "--version"]
ENTRYPOINT ["/usr/local/bin/ragnarok"]
CMD ["--help"]
