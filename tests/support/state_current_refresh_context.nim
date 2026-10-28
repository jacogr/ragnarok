# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit exact nonempty current reconstruction policy, independent of source payload ownership.
import ./state_current_request_keys_context
import ../../src/state/current_refresh_plan as state_current_refresh_plan
import ../../src/state/current_request_keys as state_current_request_keys
import ../../src/state/supplied_services as state_supplied_services
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
const currentRefreshTestLimits* = CurrentRefreshLimits(projection: SuppliedServicesLimits(
    services: ElementLimit(2), facts: ElementLimit(14), perValue: ByteLimit(3), bytes: ByteLimit(
    65536)), checks: ElementLimit(14), wireBytes: ByteLimit(230))
proc namespaceRefreshKeys*(base: OwnedReport): CurrentRequestKeys =
  ## Only actual nonempty selected-parent/genuine-update preservation supplies the planning source.
  captureCurrentRequestKeys(namespacePreservation(base), currentRequestKeyTestLimits).value
