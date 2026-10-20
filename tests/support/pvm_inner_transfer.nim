# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored cross-page byte patterns and real allocated inner maps for transfer witnesses and guards.

import ../../src/pvm/[inner_machines, machine]
import ./[pvm_inner_lifecycle, pvm_inner_pages]

proc transferRegisters*(caller = 69630'u64, inner = 69631'u64, size = 4'u64,
    id = 0'u64): RegisterFile =
  ## Preserve full-width caller/inner addresses and lengths independently of physical page ordinals.
  result = innerRegisters()
  result[7] = RegisterValue(id)
  result[8] = RegisterValue(caller)
  result[9] = RegisterValue(inner)
  result[10] = RegisterValue(size)
proc transferMemory*(): Memory =
  ## Two read-only source pages and two writable sentinel pages expose opposite endpoint permissions.
  var pages: seq[PageImage] = @[]
  for ordinal in [16'u32, 17, 48, 49]:
    var page = PageImage(index: PageIndex(ordinal), access: if ordinal < 48:
      PageAccess.ReadOnly else: PageAccess.ReadWrite, bytes: default(array[4096, byte]))
    for offset in 0..<4096: page.bytes[offset] = if ordinal <
        48: 193'u8 else: 165'u8 # Distinct unchanged prefix/suffix sentinels.
    if ordinal == 16:
      page.bytes[4094] = 61
      page.bytes[4095] = 62 # The authored transfer crosses exactly this source boundary.
    elif ordinal == 17:
      page.bytes[0] = 71
      page.bytes[1] = 72
    pages.add(page)
  captureMemory(pages, PageLimit(4)).value
proc transferMachines*(): InnerMachines =
  ## Allocate two writable pages through genuine machine/pages hosts; no detached RAM setter exists.
  innerPagesResponse(pageMachines(), MachineGas(10000), pageRegisters(count = 2), innerMemory()).value.machines
