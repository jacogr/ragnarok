# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JAMNP-S validator metadata endpoint projection. The first sixteen bytes are IPv6 and the
## next two bytes are the little-endian port; trailing validator metadata is unrelated data.

import ../quic/address

type
  EndpointError* {.pure.} = enum ## Incomplete metadata and an unavailable remote port expose no endpoint.
    Uninitialized, None, Truncated, Unavailable
  EndpointResult* = object ## Private guarded success binds the projected IP and port together.
    case status: EndpointError
    of None: completed: NetworkEndpoint
    else: discard          # No default or rejected projection grants a native destination.

func error*(outcome: EndpointResult): EndpointError =
  ## Observe failure without exposing partially copied metadata.
  outcome.status

func value*(outcome: EndpointResult): NetworkEndpoint {.requires: outcome.status ==
    EndpointError.None.} =
  ## Return only a complete fixed tuple.
  outcome.completed

proc validatorEndpoint*(metadata: openArray[byte]): EndpointResult =
  ## Bound every fixed-field read before copying; unrelated trailing metadata is ignored.
  if metadata.len < 18: return EndpointResult(status: EndpointError.Truncated)
  var ip = default(array[16, byte])
  for index in 0..<16: ip[index] = metadata[index]
  let port = uint16(metadata[16]) or (uint16(metadata[17]) shl 8)
  let address = ipv6Address(ip)
  if port == 0 or address.unspecified: return EndpointResult(status: EndpointError.Unavailable)
  EndpointResult(status: EndpointError.None, completed: networkEndpoint(address, port))
