# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# Local ARM64 qualification only; the production image and CI platform matrix remain separate.
FROM ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac
ARG TARGETARCH
RUN test "$TARGETARCH" = arm64
RUN apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 update && \
    apt-get install --no-install-recommends -y \
    build-essential ca-certificates clang lld make python3 xz-utils && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .
# Host-staged official archives are hash-verified by the ordinary installer before execution.
RUN make compiler-tools
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
CMD ["make", "check-pvm-arm64-jit-linux"]
