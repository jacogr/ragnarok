# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict Unicode scalar validation shared by byte-oriented interfaces.

from std/unicode import validateUtf8

proc validUtf8*(text: string): bool =
  ## Validate Unicode scalar encodings with the pinned stdlib's strict stateless validator.
  validateUtf8(text) == -1
