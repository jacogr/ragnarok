# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# Deliberately reject an interchangeable raw/wrong-domain digest field at compile time.
import ../../../src/codec/work_digest
var wrong = default(uint64)
var value = default(WorkDigest)
value.accumulateGas = wrong
