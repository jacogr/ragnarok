# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Address selection for explicitly configured JAM endpoints. Absent configuration preserves
## isolated proof defaults; a configured remote selects a matching-family wildcard local bind.
import ../quic/address
export address

func dialTarget*(remote: NetworkAddress, port: uint16, ipv6 = false): NetworkEndpoint =
  ## Copy a concrete destination, retaining the explicit legacy family only when no IP was supplied.
  networkEndpoint((if remote.valid: remote else: loopbackAddress(ipv6)), port)

func dialBinding*(local, remote: NetworkAddress): NetworkAddress =
  ## Explicit binding wins; configured destinations require an unrestricted same-family source socket.
  if local.valid: return local
  if remote.valid:
    if remote.ipv6: return ipv6Address(default(array[16, byte]))
    return ipv4Address([0'u8, 0, 0, 0])
  default(NetworkAddress)

func dialFamily*(local: NetworkAddress, fallback = false): bool =
  ## A selected local socket family also determines the legacy loopback target when no remote was supplied.
  if local.valid: local.ipv6 else: fallback

func validDial*(local, remote: NetworkAddress): bool =
  ## Refuse impossible native destinations before socket or certificate allocation.
  if remote.valid:
    if remote.unspecified: return false
    if local.valid and local.ipv6 != remote.ipv6: return false
  true
