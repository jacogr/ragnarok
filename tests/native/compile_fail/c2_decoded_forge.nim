# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private discriminators cannot be supplied through an external variant constructor.
import ../../../src/codec/[c2_records, composite]
discard AccumulationValue(inputKind: AccumulationKind.Transfer)
