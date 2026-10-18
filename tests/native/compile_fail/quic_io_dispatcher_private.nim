# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A caller cannot insert arbitrary descriptors into a dispatcher's registration storage.
import ../../../src/quic/io
let dispatcher = newDispatcher()
discard dispatcher.descriptors
