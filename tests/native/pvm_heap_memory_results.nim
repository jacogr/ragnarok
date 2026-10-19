# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed writable-page counts and range updates cannot expose values or partial memory owners.

import std/cmdline
import ../../src/pvm/machine
let empty = captureMemory([], PageLimit(0)).value
case paramStr(1)
of "count-owner":
  discard writablePageCount(default(Memory), PageIndex(0), PageIndex(1)).value # Invalid provenance.
of "count-range":
  discard writablePageCount(empty, PageIndex(2), PageIndex(1)).value # No count for a reversed interval.
of "map-owner":
  discard withWritablePages(default(Memory), PageIndex(0), PageIndex(1)).value # No default successor.
of "map-range":
  discard withWritablePages(empty, PageIndex(0), PageIndex(high(uint32))).value # No narrowed endpoint.
else:
  discard withWritablePages(empty, PageIndex(0), PageIndex(1)).value # No partial allocation at the cap.
