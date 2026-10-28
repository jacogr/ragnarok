# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict runtime guards reject extraction from failed/default transfer collection alternatives.

import std/cmdline
import std/syncio
import ../../src/codec/bounded as codec_bounded
import ../../src/state/accumulation_transfers as state_accumulation_transfers
import ../../src/state/accumulation_outcome as state_accumulation_outcome
import ../../src/state/accumulation_annulment as state_accumulation_annulment
let argument = paramStr(1)
let absent = default(PreparedAccumulationTransfers)
case argument
of "selection": discard absent.transferCollectionAnnulment.value # No default accpar certificate.
of "ordinary-selection":
  let ordinary = prepareAccumulationTransfers([], AccumulationTransferCollectionLimits())
  if ordinary.error != AccumulationTransferCollectionError.None: quit(
      3) # A setup refusal cannot impersonate the required extraction guard.
  discard ordinary.value.transferCollectionAnnulment.value # A genuine unbound collection has NoAnnulment.
of "invalid-selection":
  discard prepareAnnulmentTransfers(default(PreparedAccumulationAnnulment),
      AccumulationTransferCollectionLimits()).value # No default conflict source can initialize output.
of "info":
  discard absent.transferCollectionInfo.value # Missing owner exposes no copied counts.
of "source":
  discard absent.transferCollectionSourceAt(AccumulationTransferSourceIndex(0)).value # No fabricated outcome.
of "transfer":
  discard absent.collectedTransferAt(CollectedTransferIndex(0)).value # No fabricated transfer.
of "index":
  let empty = prepareAccumulationTransfers([], AccumulationTransferCollectionLimits()).value
  discard empty.collectedTransferAt(CollectedTransferIndex(high(uint64))).value # Full-width invalid ordinal.
of "limit":
  let missing = default(AccumulationOutcome)
  discard prepareAccumulationTransfers([missing], AccumulationTransferCollectionLimits()).value # Source limit refuses before inspection.
of "failed":
  let missing = default(AccumulationOutcome)
  let limits = AccumulationTransferCollectionLimits(sources: ElementLimit(1))
  discard prepareAccumulationTransfers([missing], limits).value # Valid count reaches the invalid outcome refusal.
of "source-index":
  let empty = prepareAccumulationTransfers([], AccumulationTransferCollectionLimits()).value
  discard empty.transferCollectionSourceAt(AccumulationTransferSourceIndex(high(
      uint64))).value # No fabricated source at a huge ordinal.
else:
  var result = prepareAccumulationTransfers([], AccumulationTransferCollectionLimits())
  if argument == "default":
    result = default(AccumulationTransferCollectionResult[
        PreparedAccumulationTransfers]) # Dynamic selection preserves the runtime guard.
  discard result.value # Default has no selected success.
