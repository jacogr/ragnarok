# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One non-copyable owner and startup path for the application's telemetry, RPC and UI services.
## The peer dispatcher borrows individual fields only while this stack owner remains stable;
## transport callbacks must retire before close/destruction. A bounded chain snapshot is shared once.

import std/[syncio, strutils, base64]
import ./options
import ../telemetry/[wire, client, chain]
import ../quic/transport
import ../rpc/[server, protocol]
import ../chain/[parameters, genesis]
import ../ui/server

type Services* = object ## Owns listeners/exporter; fields are borrowed by synchronous peer callbacks.
  rpc*: Server
  ui*: UiServer
  telemetry*: Client
  chainText: string

proc `=copy`*(destination: var Services, source: Services) {.error: "Application Services owns descriptors".}
proc `=destroy`*(services: Services) =
  ## Retire partially configured owners and the shared snapshot even without explicit shutdown.
  `=destroy`(services.ui)
  `=destroy`(services.rpc)
  `=destroy`(services.telemetry)
  `=destroy`(services.chainText)

proc close*(services: var Services) =
  ## Idempotent retirement happens after every dispatcher/native callback has ended its borrows.
  services.ui.close()
  services.rpc.close()
  services.telemetry.close()
  services.chainText = ""

# Read at most limit+1 bytes; empty output means missing, empty or oversized configuration.
proc boundedFile(path: string, limit: int): string {.raises.} =
  result = ""
  var file: File = nil
  if path.len == 0 or not open(file, path, fmRead): return # No implicit file/default chain.
  defer: close(file) # All read outcomes retire the handle.
  var text = newString(limit + 1)
  let buffer = text.beginStore(text.len)
  let count = readBuffer(file, cast[pointer](buffer), text.len)
  text.endStore() # Commit the public string bulk-write API before reading or resizing.
  if count <= 0 or count > limit: return # Detect growth/oversize without unbounded readFile.
  text.setLen(count)
  result = move(text)

proc setupRpc(rpc: var Server, options: Options, role: string, text: string): bool =
  ## An explicit RPC chain must validate before opening the listener; missing configuration remains unavailable.
  var parameters = default(ParameterResult)
  var genesis = unavailableGenesis()
  if options.rpcPort() != 0 and options.chainPath().len > 0:
    parameters = configuredParameters(text)
    if not parameters.ok: return false # Fail startup rather than advertise a partial/default parameter set.
    genesis = configuredGenesis(text, parameters.value)
    if genesis.error == GenesisError.Invalid: return false # Reject an incomplete or malformed explicit genesis.
  rpc.start(options.rpcPort(), role, parameters, genesis, options.uiPort())

proc setupTelemetry(client: var Client, options: Options, certificate: string, port: uint16,
    ipv6: bool, text: string): bool {.raises.} =
  ## Build registration from explicit JIP-4 configuration and the actual local certificate/socket.
  if not options.telemetryEnabled(): return true # Absence is the default and requires no configuration.
  if text.len == 0: return false # Never invent a chain or use an implicit development network.
  let pem = boundedFile(certificate, 16384).strip()
  const beginMarker = "-----BEGIN CERTIFICATE-----"
  const endMarker = "-----END CERTIFICATE-----"
  # Reject overlapping/empty PEM markers before constructing the body slice.
  if pem.len < beginMarker.len + endMarker.len: return false
  if not pem.startsWith(beginMarker) or not pem.endsWith(endMarker): return false
  var body = ""
  # Permit PEM whitespace but reject noncanonical base64 through round-trip validation below.
  for character in pem[beginMarker.len..<pem.len - endMarker.len]:
    if character notin {' ', '\t', '\r', '\n'}: body.add(character)
  var der = base64.decode(body)
  if der.len == 0 or der.len > 8192 or base64.encode(der) != body: return false
  # The native extractor initializes all C fields before success; no C array object constructor is used.
  var fields {.noinit.}: CertFields
  # Reuse maintained X.509 extraction; public identity is copied, never read from a secret key.
  let derPointer = der.toCString()
  if parseCert(cast[ptr byte](derPointer), csize_t(der.len), addr fields) != 1 or
      fields.edKey != 1 or fields.keyLength != 32: return false
  var address = default(array[16, byte])
  if ipv6:
    address[15] = 1 # The proof peer binds only ::1 in its IPv6 modes.
  else:
    # JIP-3 represents IPv4 endpoints as IPv4-mapped IPv6 addresses.
    address[10] = 255
    address[11] = 255
    address[12] = 127
    address[15] = 1
  var identity = default(array[32, byte])
  # Copy C array elements individually into native Nim storage before crossing the API boundary.
  for i in 0..<32: identity[i] = fields.key[i]
  let parsed = chainMetadata(text, identity, address, port)
  if not parsed.ok: return false # Failed chain metadata cannot produce a registration.
  configure(client, options.telemetryEndpoint(), parsed.value)

proc start*(services: var Services, options: Options, role: string): bool {.raises.} =
  ## Open optional listeners once, using the same bounded chain snapshot for RPC and telemetry.
  if not options.valid(): return false
  if not services.ui.start(options.uiPort(), options.devUiDirectory()):
    stderr.writeLine("Invalid UI listener or --dev-ui-dir")
    services.close() # Failed startup cannot retain a directory or partially opened listener.
    return false
  services.chainText = boundedFile(options.chainPath(), MaxChainBytes)
  if not services.rpc.setupRpc(options, role, services.chainText):
    stderr.writeLine("Invalid RPC listener or --chain parameters")
    services.close() # RPC parameter/root failures also retire an already opened UI listener.
    return false
  true

proc configureTelemetry*(services: var Services, options: Options, certificate: string,
    port: uint16, ipv6: bool): bool {.raises.} =
  ## Register the actual transport identity/address after binding, using the captured chain bytes.
  setupTelemetry(services.telemetry, options, certificate, port, ipv6, services.chainText)
