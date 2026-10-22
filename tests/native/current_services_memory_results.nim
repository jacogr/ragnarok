# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A default Services owner has no completed current handoff to acknowledge.
import ../../src/app/services
var owner = default(Services)
discard owner.takeCurrentAccumulation()
