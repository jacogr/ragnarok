# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JAMNP-S unique-persistent stream admission and replacement policy. QUIC supplies copied
## stream numbers; connection-initiator and greatest-ID requirements remain Nim decisions.

import ../quic/transport

proc persistentInitiator*(number: NativeStreamId): bool =
  ## UP streams must be bidirectional and opened by the connection initiator (the QUIC client).
  let value = uint64(number)
  value < (1'u64 shl 62) and (value and 3) == 0

proc preferPersistent*(candidate, existing: NativeStreamId): bool =
  ## Among simultaneous UP streams of one kind on one connection, keep the greatest stream ID.
  persistentInitiator(candidate) and persistentInitiator(existing) and
    uint64(candidate) > uint64(existing)
