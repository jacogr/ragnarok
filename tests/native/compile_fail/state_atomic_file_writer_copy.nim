# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Generic native ownership rejects duplication during actual ARC lowering.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <AtomicFileWriter>", "build_name": "state-atomic-file-writer-copy"}
import ../../../src/lib/atomic/file/writer as atomic_file_writer
var original = default(AtomicFileWriter)
var duplicate = original
discard original.close()
discard duplicate.close()
