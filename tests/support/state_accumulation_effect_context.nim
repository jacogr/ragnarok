# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored native test preparation for checkpoint/yield cases and strict result-extraction probes.
## preparedEffectContexts builds a genuine public-API initial I over a complete synthetic map with incoming credit.

import ../../src/state/accumulation_context as state_accumulation_context
import ../../src/state/accumulation_invocation as state_accumulation_invocation
import ../../src/state/accumulation_service as state_accumulation_service
import ../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../src/state/accumulation_operands as state_accumulation_operands
import ../../src/state/accumulation_queue as state_accumulation_queue
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/assurances as codec_assurances
import ../../src/codec/composite as codec_composite
import ../../src/codec/header as codec_header
import ../../src/codec/work_digest as codec_work_digest
import ../../src/codec/c2_records as codec_c2_records
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/codec/state_authorization as codec_state_authorization
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/codec/state_privileges as codec_state_privileges
import ../../src/codec/state_workqueues as codec_state_workqueues
import ../../src/codec/state_service_values as codec_state_service_values
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/state_layout as codec_state_layout
import ../../src/crypto/primitives as crypto_primitives

proc preparedEffectContexts*(extra: seq[StateEntry] = @[]): PreparedAccumulationContexts =
  ## Construct a real credited account and exact tiny-profile components; this is not a published whole-chain state.
  let queue = planAccumulationQueues([], [0'u8], [0'u8], HeaderSlot(0),
    AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(2), epochSlots: EpochSlots(1),
      maxBytes: ByteLimit(1000)))).value
  let operands = prepareAccumulationOperands(queue, AccumulationReportPrefix(0), default(
    AccumulationOperandConfig)).value
  let inputs = prepareAccumulationInputs(operands,
    [DeferredTransfer(source: ServiceIndex(99), destination: ServiceIndex(42),
        amount: TransferBalance(7))],
    [], AccumulationInputConfig(inputs: ElementLimit(1), services: ElementLimit(1))).value
  let config = AccumulationContextConfig(validators: ValidatorCount(6),
    queues: AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(160),
        maxBytes: ByteLimit(5120)),
    staging: ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
        maxBytes: ByteLimit(2017)),
    privileges: PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(0),
        maxBytes: ByteLimit(100)),
    totalBytes: ByteLimit(10000))
  let raw = @[0'u8]
  let hash = array[32, byte](blake2b256(raw).value)
  let rows = @[newSeq[AuthorizerHash](80), newSeq[AuthorizerHash](80)]
  var entries = @[authorizationEntry(AuthorizationKind.Queues, rows, config.queues).value,
    validatorEntry(ValidatorChapter.Staging, newSeq[StateValidator](6), config.staging).value,
    privilegeStateEntry(PrivilegeState(manager: ServiceIndex(11), delegator: ServiceIndex(12),
      registrar: ServiceIndex(13), assigners: @[ServiceIndex(14), ServiceIndex(15)]),
          config.privileges).value,
    serviceMetadataEntry(ServiceIndex(42), ServiceMetadata(codeHash: CodeHash(hash),
      balance: AccountBalance(10), lastAccumulation: AccountSlot(3)), ByteLimit(
          ServiceMetadataBytes)).value,
    servicePreimageEntry(ServiceIndex(42), ServicePreimageHash(hash), raw,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).value,
    StateEntry(key: chapterKey(StateChapter(250)), value: @[9'u8, 4, 2])]
  # Extra authored records participate in the complete source root before any preparation or credit.
  for entry in extra: entries.add(entry)
  let state = newStateStore(entries, StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(100),
    perValue: ByteLimit(10000), totalValueBytes: ByteLimit(10000), nodes: TrieNodeLimit(10000)),
    writes: ElementLimit(1), writeValueBytes: ByteLimit(ServiceMetadataBytes))).value.snapshot.value
  let service = prepareAccumulationService(inputs, InvocationServiceIndex(0), state, HeaderSlot(4),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(0), preimageBytes: ByteLimit(1))).value
  let invocation = prepareAccumulationInvocation(service, default(StateEntropyWord),
      ServiceProbeLimit(1)).value
  prepareAccumulationContexts(invocation, config).value
