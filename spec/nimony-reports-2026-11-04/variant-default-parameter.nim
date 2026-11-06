# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Omitted variant defaults must select the same false branch as an explicit default value.
type Value = object
  case present: bool
  of true: payload: int
  else: discard
proc take(value = default(Value)) = discard
take()
