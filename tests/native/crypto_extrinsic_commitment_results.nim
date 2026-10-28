# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and actually refused commitments cannot expose a digest.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/assertions
import std/cmdline
import std/syncio
import ../../src/crypto/extrinsic_commitment as crypto_extrinsic_commitment
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/header as codec_header
import ../../src/codec/bounded as codec_bounded
let outcome = if paramStr(1) == "default": default(ExtrinsicCommitmentResult[ExtrinsicRoot]) else:
  extrinsicCommitment(default(OwnedExtrinsic), ByteLimit(100))
assert outcome.error == (if paramStr(1) == "default": ExtrinsicCommitmentError.Uninitialized else: ExtrinsicCommitmentError.InvalidOwner)
echo array[32, byte](outcome.value)[0]
