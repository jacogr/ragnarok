# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_assurance_services_arc_release"}

## Genuine full-state Services owns the namespace at its final address and retires mutable startup leases before cached accounting, RPC resumption or descriptor cleanup.

import std/[assertions, syncio, dirs, paths, monotimes, times]
import std/posix/posix
import ../../../src/app/[services, options]
import ../../../src/app/proof/[worker, assurance_storage]
import ../../../src/jamnp-s/[assurance_store, assurance_record, availability_proof]
import ../../../src/chain/network_identity
import ../../../src/codec/bounded
import ../../../src/rpc/server
import ../../../src/lib/atomic/file
import ../../support/[proof_query_context, arc_evidence]
from ../../support/storage_io import storageProcessId

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield only between synchronized worker-state observations under one bounded deadline.

proc limits(): AssuranceStoreLimits =
  ## Independent explicit retention capacity and verification ceilings enable no namespace implicitly.
  AssuranceStoreLimits(entries: ElementLimit(4), scanEntries: ElementLimit(300),
    bytes: ByteLimit(64000000), record: AssuranceRecordLimits(bytes: ByteLimit(16000000),
      verification: AvailabilityMerkleLimits(bytes: ByteLimit(64000000),
        hashes: ElementLimit(10000), hashBytes: ByteLimit(64000000))))

proc waitDone(owner: var Services) =
  ## Host ticks remain available but must not read the mutable namespace or canonical graph.
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "managed assurance completion deadline"
    assert not owner.assuranceStorageInfo.opened, "cached accounting cannot publish a running owner"
    owner.tick(0)
    discard pauseMicros(100)

proc namespace(folder: string, chain: AssuranceChainId, busy: bool) =
  ## An independent owner witnesses actual descriptor exclusion or release after exact collection/join.
  var contender = default(AssuranceStore)
  defer: discard contender.close()
  let opened = contender.openAssuranceStore(folder, chain, limits())
  if busy:
    # Cached host metadata alone cannot prove the actual single-writer native gate remains held.
    assert opened.error == AssuranceStoreError.FileFailure, "actual namespace is locked"
    assert opened.fileError == AtomicFileError.Busy, "another owner cannot steal the writer"
  else:
    # A cancelled completed open must release the real lock, not merely clear a host boolean.
    assert opened.error == AssuranceStoreError.None, "native namespace lease released"
    assert contender.len == 0 and contender.byteLength == 0, "cancellation preserves empty published namespace"

proc cycle(owner: var Services, missing: string, index: int) {.raises.} =
  ## Failed I/O and Done cancellation both keep shared capacity until the matching exact ticket retires.
  let admitted = owner.beginAssuranceStorage(missing, limits(), AssuranceStorageMode.Open)
  assert admitted.error == AssuranceStorageStartError.None, "bounded missing-path job admitted"
  assert owner.stateProofActive and owner.rpc.chainPaused, "native startup owns the canonical/RPC gate"
  owner.waitDone()
  if index mod 2 == 0: assert owner.cancelStateProof(admitted.value), "cancel exact completed startup"
  let completed = owner.collectStateProof(admitted.value)
  if index mod 2 == 0:
    # A hidden result still requires joined mutation retirement before the host may touch the native owner.
    assert completed.kind == ProofWorkerCompletionKind.Cancelled, "cancelled startup exposes no successful owner"
  else:
    # The actual missing-directory failure must survive collection without a fabricated success receipt.
    assert completed.kind == ProofWorkerCompletionKind.AssuranceCompleted, "typed storage completion"
    assert completed.assuranceStorageValue.error == AssuranceStoreError.InvalidNamespace, "actual I/O refusal preserved"
  assert not owner.assuranceStorageInfo.opened and not owner.stateProofActive and
      not owner.rpc.chainPaused, "exact failure retirement resumes canonical access"

proc main() {.raises.} =
  ## Configured original genesis independently binds the namespace; no raw chain parameter can substitute a later head.
  let context = queryContext()
  let suffix = $storageProcessId()
  var chainFile = "assurance-services-chain-" & suffix & ".json"
  let folder = "assurance-services-store-" & suffix
  let missing = "missing-assurance-services-" & suffix
  writeFile(chainFile, context.text)
  defer:
    discard posix.unlink(chainFile.toCString())
    removeDir(path(folder)) # All declared Services/native owners retire before test-owned files.
  let configured = readNetworkIdentity(context.text)
  assert configured.error == NetworkIdentityError.None, "genuine configured network identity"
  let chain = AssuranceChainId(array[32, byte](configured.value.genesisHash))
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--chain", chainFile, "--with-state",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], options)
  var owner = default(Services)
  defer: owner.close()
  assert owner.beginAssuranceStorage(folder, limits(), AssuranceStorageMode.Create).error ==
      AssuranceStorageStartError.Closed, "closed Services cannot create files"
  assert owner.start(options, "assurance storage services"), "genuine complete-state startup"
  assert not owner.assuranceStorageInfo.opened, "ordinary startup leaves assurance storage disabled"
  let invalid = owner.beginAssuranceStorage(folder, default(AssuranceStoreLimits),
      AssuranceStorageMode.Create)
  assert invalid.error == AssuranceStorageStartError.CaptureFailure, "invalid explicit policy refused"
  assert invalid.captureError == AssuranceStorageJobError.InvalidPolicy, "actual capture refusal preserved"
  assert not owner.stateProofActive and not owner.rpc.chainPaused, "capture refusal has no lease"
  let foreignLease = owner.rpc.pauseChain()
  assert foreignLease != nil, "independent RPC suspension"
  assert owner.beginAssuranceStorage(folder, limits(), AssuranceStorageMode.Create).error ==
      AssuranceStorageStartError.Busy, "foreign RPC lease blocks storage admission"
  assert owner.rpc.resumeChain(foreignLease), "only foreign owner resumes its lease"
  let created = owner.beginAssuranceStorage(folder, limits(), AssuranceStorageMode.Create)
  assert created.error == AssuranceStorageStartError.None, "explicit namespace creation admitted"
  assert owner.stateProofActive and not owner.preparationAvailable, "storage shares canonical capacity"
  assert owner.beginAssuranceStorage(folder, limits(), AssuranceStorageMode.Open).error ==
      AssuranceStorageStartError.Busy, "a second job cannot inspect a mutating owner"
  owner.stopPreparation()
  assert owner.stateProofActive and owner.rpc.chainPaused, "another subsystem cannot retire storage exclusion"
  assert owner.collectStateProof(default(ProofWorkerTicket)).kind ==
      ProofWorkerCompletionKind.Uninitialized, "foreign collection cannot touch namespace ownership"
  owner.waitDone()
  assert not owner.assuranceStorageInfo.opened, "Done alone cannot publish host accounting"
  let completed = owner.collectStateProof(created.value)
  assert completed.kind == ProofWorkerCompletionKind.AssuranceCompleted, "exact storage collection"
  assert completed.assuranceStorageValue.error == AssuranceStoreError.None, "real synchronized creation"
  let info = owner.assuranceStorageInfo
  assert info.opened and info.records == 0 and info.bytes == 0, "post-collection scalar accounting"
  assert not owner.rpc.chainPaused and owner.stateProofAvailable, "exact collection resumes the host"
  owner.stopStateProofs()
  assert owner.assuranceStorageInfo.opened, "unrelated idle proof stop preserves installed storage"
  namespace(folder, chain, true)
  assert owner.beginAssuranceStorage(folder, limits(), AssuranceStorageMode.Open).error ==
      AssuranceStorageStartError.Busy, "an installed namespace cannot be replaced"
  owner.close()
  assert not owner.assuranceStorageInfo.opened, "joined Services close clears cached metadata"
  namespace(folder, chain, false)
  assert owner.start(options, "assurance storage restart"), "same final-address owner restarts"
  let cancelled = owner.beginAssuranceStorage(folder, limits(), AssuranceStorageMode.Open).value
  owner.waitDone()
  assert owner.cancelStateProof(cancelled), "Done cancellation after actual open"
  assert owner.stateProofActive and owner.rpc.chainPaused, "cancellation retains exclusive capacity"
  assert owner.collectStateProof(created.value).kind == ProofWorkerCompletionKind.Uninitialized, "stale collection cannot close a newer store"
  assert owner.collectStateProof(cancelled).kind == ProofWorkerCompletionKind.Cancelled, "cancelled exact result"
  assert not owner.assuranceStorageInfo.opened and not owner.rpc.chainPaused, "completed cancelled owner cleaned before resume"
  namespace(folder, chain, false)
  let joined = owner.beginAssuranceStorage(folder, limits(), AssuranceStorageMode.Open).value
  owner.waitDone()
  owner.stopStateProofs()
  assert not owner.assuranceStorageInfo.opened and not owner.rpc.chainPaused, "joined stop closes uncollected Done storage"
  assert owner.collectStateProof(joined).kind == ProofWorkerCompletionKind.Uninitialized, "joined generation retired"
  namespace(folder, chain, false)
  discard owner.beginAssuranceStorage(folder, limits(), AssuranceStorageMode.Open).value
  owner.close() # Queued/Running/Done all join before native namespace or canonical address retirement.
  namespace(folder, chain, false)
  assert owner.start(options, "assurance storage release"), "joined cleanup permits restart"
  cycle(owner, missing, 1)
  let before = getOccupiedMem()
  for index in 0..<1000:
    # Alternating failed/cancelled jobs release private paths and exact RPC tokens without accumulating ARC owners.
    cycle(owner, missing, index)
  let after = getOccupiedMem()
  assert before == after, "managed assurance Services ARC release"
  recordArcRelease("jamnp_assurance_services", 1000, before, after)
  echo "JAMNP-S assurance services passed"
try:
  main()
except:
  quit(2) # A real startup, filesystem or ownership failure fails the suite.
