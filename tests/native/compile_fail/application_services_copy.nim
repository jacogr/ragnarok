# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Services duplication must fail actual ARC lowering, including its newly private worker-shared TLS signing key.

# @@Verification={"group":"ownership_compile","build_name":"application-services-copy","expected":"'=dup' is not available for type <Services>","rationale":"Services owns a private signing key shared with a fixed-address CPU worker; copying the aggregate could retire that key or its worker before the original lease joins.","reference":"spec/jamnp-report-guarantees.md"}
import ../../../src/app/services

proc duplicated(source: Services): Services =
  ## Returning a borrowed aggregate must not duplicate private signer, worker or descriptor lifetime authority.
  source
var first = default(Services)
var second = duplicated(first)
discard first.workSigningConfigured
second.close()
