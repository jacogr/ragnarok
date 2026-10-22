# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused selected physical descriptors cannot expose sources, counters or final bytes.
import std/cmdline
import ../../src/state/[accumulation_selected_writes, accumulation_account_selection,
    accumulation_creation_union]
let argument = paramStr(1)
let owner = default(PreparedSelectedAccountWrites)
let refused = if argument == "default": default(SelectedAccountWriteResult[PreparedSelectedAccountWrites])
  else: prepareSelectedAccountWrites(default(PreparedAccumulationAccountSelection), default(
      PreparedAccumulationCreationUnion), default(SelectedAccountWriteLimits))
case argument
of "info": discard owner.selectedWritesInfo.value # No false empty accounting.
of "prior": discard owner.selectedWritesPriorSource.value # No fabricated M certificate.
of "new": discard owner.selectedWritesNewSource.value # No fabricated n certificate.
of "write": discard owner.selectedWriteAt(AccumulationSelectedWriteIndex(0)).value # No false physical descriptor.
else: discard refused.value # Failed/default results retain reasons alone.
