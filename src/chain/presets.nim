# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical GP0.8 Tiny/Full and experimental issue215 Fuzz parameters are selected once at startup.
## The catalog owns every protocol scalar and the explicit Fuzz D interpretation; resource limits remain separate.
import ./parameters

type ChainPreset* {.pure.} = enum Tiny, Full, Fuzz ## Named protocol presets never select mutable global state.

proc presetParameters*(preset: ChainPreset): ParameterResult =
  ## Build one immutable complete Appendix B tuple from Full plus the explicitly documented preset overrides.
  var values: array[Parameter, uint64] = [10'u64, 1, 100, 341, 19200, 600, 10000000, 50000000,
    5000000000'u64, 3500000000'u64, 8, 16, 8, 16, 14400, 8, 6, 80, 10, 128, 5, 64000, 13791360,
    4000000, 3072, 49152, 128, 3072, 500]
  case preset
  of ChainPreset.Full:
    discard # Every Full scalar is already supplied by the pinned Appendix B definitions.
  of ChainPreset.Tiny:
    values[coreCount] = 2
    values[minTurnaroundPeriod] = 32
    values[epochPeriod] = 12
    values[maxRefineGas] = 1000000000
    values[blockGasLimit] = 20000000
    values[maxTicketsPerBlock] = 3
    values[maxLookupAnchorAge] = 24
    values[rotationPeriod] = 4
    values[epochTailStart] = 10
  of ChainPreset.Fuzz:
    values[coreCount] = 85
    values[minTurnaroundPeriod] = 900
    values[epochPeriod] = 60
    values[maxRefineGas] = 1250000000
    values[blockGasLimit] = 875000000
    values[maxTicketsPerBlock] = 4
    values[maxLookupAnchorAge] = 600
    values[rotationPeriod] = 5
    values[epochTailStart] = 50
  const widths = [8, 8, 8, 2, 4, 4, 8, 8, 8, 8, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2, 4, 4, 4, 4, 4, 4, 4, 4]
  var wire = default(array[ParameterBytes, byte])
  var offset = 0
  for field in low(Parameter)..high(Parameter):
    # All catalog values fit their exact fetch widths; the fixed reviewed extent is122 bytes.
    for index in 0..<widths[ord(field)]:
      wire[offset+index] = byte((values[field] shr (8*index)) and 255)
    offset += widths[ord(field)]
  let decoded = decodeParameters(wire)
  if not decoded.ok: return decoded
  if preset == ChainPreset.Fuzz:
    # Maintainer-authorized issue215 exception: D900 overrides the canonical D=L+4800 relation only here.
    return withExplicitExpungePeriod(decoded.value)
  decoded
