## Tagged shape/result guards, fixed scope copies and explicit request-namespace overlap evidence.
import ../../src/[state_requests, state_service_values, state_trie, bounded]

## Failed/default results must retain inactive-success-field protection in checked optimized builds.
proc guarded[T](value: RequestResult[T]) =
  var caught = false
  try:
    discard value.value # Failure cannot masquerade as a valid empty requested history.
  except FieldDefect:
    caught = true # Runtime field guards remain enabled under ARC/Clang LTO.
  doAssert caught

## A decoded fixed tagged history survives source mutation, caller-input destruction and local scope exit.
proc captured(config: RequestEntryConfig): RequestHistoryRead =
  var source = RequestHistory(state: RequestState.Reavailable, originalFrom: RequestSlot(high(uint32)),
    removedAt: RequestSlot(0), restoredAt: RequestSlot(128))
  let entry = serviceRequestEntry(ServiceIndex(1729), default(ServicePreimageHash), RequestLength(
      256), source, config)
  doAssert entry.error == RequestError.None and entry.value.value.len == 13
  source = default(RequestHistory)
  var input = entry.value.value
  let parsed = decodeRequestHistory(input, config.history)
  doAssert parsed.error == RequestError.None
  result = parsed.value
  for i in 0..<input.len: input[i] = 0 # Returned fields are independent fixed copies.

## Validate active fields, impossible reads, strict policies and deterministic namespace overlaps without new restrictions.
proc main() =
  let config = RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
      items: ElementLimit(3), maxBytes: ByteLimit(13)))
  let value = captured(config)
  doAssert value.consumed == 13 and value.history.state == RequestState.Reavailable
  doAssert uint32(value.history.originalFrom) == high(uint32) and uint32(value.history.removedAt) ==
      0 and uint32(value.history.restoredAt) == 128
  var copy = value.history
  copy.restoredAt = RequestSlot(0)
  doAssert uint32(value.history.restoredAt) == 128
  let requested = decodeRequestHistory(@[0'u8], config.history)
  doAssert requested.error == RequestError.None and requested.value.history.state ==
      RequestState.Requested
  var wrongField = false
  try:
    discard requested.value.history.since # Requested mode must not fabricate a default supplied-at timestamp.
  except FieldDefect:
    wrongField = true # Tagged history alternatives protect application state after successful decode too.
  doAssert wrongField
  let available = decodeRequestHistory(@[1'u8, 0, 0, 0, 0], config.history)
  doAssert available.error == RequestError.None and available.value.history.state ==
      RequestState.Available
  wrongField = false
  try:
    discard available.value.history.removedAt # One-slot histories cannot expose restored-mode fields.
  except FieldDefect:
    wrongField = true # Preserve the correct payload shape independently of numeric timestamp values.
  doAssert wrongField
  guarded(default(RequestResult[RequestHistoryRead]))
  let excess = decodeRequestHistory(@[4'u8], config.history)
  doAssert excess.error == RequestError.InvalidCount
  guarded(excess)
  let short = decodeRequestHistory(@[3'u8, 0, 0, 0, 0], config.history)
  doAssert short.error == RequestError.Truncated
  guarded(short)
  let limited = serviceRequestEntry(ServiceIndex(0), default(ServicePreimageHash), RequestLength(0),
      value.history,
    RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(
        2), maxBytes: ByteLimit(13))))
  doAssert limited.error == RequestError.LimitExceeded
  guarded(limited)
  let hash = default(ServicePreimageHash)
  let requestPreimage = serviceRequestEntry(ServiceIndex(0), hash, RequestLength(high(uint32)-1),
      default(RequestHistory), config)
  let preimage = servicePreimageEntry(ServiceIndex(0), hash, @[], ServiceEntryLimits(
      keyBytes: ByteLimit(32), valueBytes: ByteLimit(0)))
  doAssert requestPreimage.error == RequestError.None and preimage.error == ServiceValueError.None
  doAssert array[31, byte](requestPreimage.value.key) == array[31, byte](preimage.value.key)
  let requestStorage = serviceRequestKey(ServiceIndex(0), hash, RequestLength(high(uint32)),
      ByteLimit(32))
  let storage = serviceStorageKey(ServiceIndex(0), array[32, byte](hash), ByteLimit(32))
  doAssert requestStorage.error == RequestError.None and storage.error == ServiceValueError.None
  doAssert array[31, byte](requestStorage.value) == array[31, byte](storage.value)
  let combined = stateTrieRoot([requestPreimage.value, preimage.value], StateTrieLimits(
      items: ElementLimit(2), perValue: ByteLimit(13),
    totalValueBytes: ByteLimit(26), nodes: TrieNodeLimit(1000)))
  doAssert combined.error == StateTrieError.DuplicateKey # Composition rejects overlapping mappings instead of silently overwriting one.
  echo "PASS requests: tagged fields, fixed scope copies, failure guards and explicit key-overlap/duplicate rejection"

main()
