## Supplementary runtime contracts for copied roots and guarded failure-only variants.
import ../../src/[state_trie, state_layout, bounded]

## Assert inactive commitment fields retain Nim's checked variant guard.
proc guarded(parsed: StateTrieResult[StateTrieCommitment]) =
  var caught = false
  try:
    discard parsed.value # Neither a default result nor a rejected mapping has a commitment.
  except FieldDefect:
    caught = true # Runtime field checks must remain enabled in the optimized build.
  doAssert caught

## Exercise public ownership/result contracts independently of the batch oracle's root comparisons.
proc main() =
  let limits = StateTrieLimits(items: ElementLimit(2), perValue: ByteLimit(33),
    totalValueBytes: ByteLimit(66), nodes: TrieNodeLimit(250))
  guarded(default(StateTrieResult[StateTrieCommitment]))
  var entries = @[StateEntry(key: StateKey(default(array[31, byte])), value: @[1'u8, 2, 3])]
  let parsed = stateTrieRoot(entries, limits)
  doAssert parsed.error == StateTrieError.None
  let saved = array[32, byte](parsed.value.root)
  entries[0].value[0] = 255
  entries.setLen(0)
  doAssert array[32, byte](parsed.value.root) == saved
  let empty = stateTrieRoot(entries, default(StateTrieLimits))
  doAssert empty.error == StateTrieError.None
  doAssert empty.value.nodes == 0 and empty.value.entries == 0
  doAssert array[32, byte](empty.value.root) == default(array[32, byte])
  entries = @[StateEntry(), StateEntry()]
  let rejected = stateTrieRoot(entries, limits)
  doAssert rejected.error == StateTrieError.DuplicateKey
  guarded(rejected)
  let limited = stateTrieRoot(entries, default(StateTrieLimits))
  doAssert limited.error == StateTrieError.LimitExceeded
  guarded(limited)
  echo "PASS state trie native: copied roots, empty identity, default/failure field guards"

main()
