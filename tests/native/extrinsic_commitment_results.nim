# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and actually refused commitments cannot expose a digest.
import std/[assertions, cmdline, syncio]
import ../../src/crypto/extrinsic_commitment
import ../../src/codec/[block_codec, header, bounded]
let outcome = if paramStr(1) == "default": default(ExtrinsicCommitmentResult[ExtrinsicRoot]) else:
  extrinsicCommitment(default(OwnedExtrinsic), ByteLimit(100))
assert outcome.error == (if paramStr(1) == "default": ExtrinsicCommitmentError.Uninitialized else: ExtrinsicCommitmentError.InvalidOwner)
echo array[32, byte](outcome.value)[0]
