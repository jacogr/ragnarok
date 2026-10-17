## Isolated default/failed public commitments and private child hashes require supported success contracts.
import std/[assertions, cmdline, syncio]
include ../../src/codec/state_trie

# Sequential test-only backend refusal is absent from the production-linked root corpus.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
# Delayed refusal tests a failure after a complete child hash already exists.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# Construct each actual failure independently, without fabricating unsafe sequence descriptors for LengthOverflow.
proc rejected(origin: string): StateTrieResult[StateTrieCommitment] =
  var second = default(array[31, byte])
  second[0] = 128
  let source = @[StateEntry(key: default(StateKey), value: newSeq[byte](33)),
    StateEntry(key: StateKey(second), value: newSeq[byte](33))]
  var limits = StateTrieLimits(items: ElementLimit(2), perValue: ByteLimit(33),
    totalValueBytes: ByteLimit(66), nodes: TrieNodeLimit(3))
  case origin
  of "default":
    # An uninitialized result contains no fabricated root or progress.
    return default(StateTrieResult[StateTrieCommitment])
  of "item-limit":
    # Entry policy rejects before input-derived scratch allocation.
    limits.items = ElementLimit(1)
  of "per-value-limit":
    # Individual payload policy rejects before any hashing.
    limits.perValue = ByteLimit(32)
  of "total-value-limit":
    # Aggregate policy rejects a sum one byte beyond its explicit ceiling.
    limits.totalValueBytes = ByteLimit(65)
  of "node-limit":
    # The exact three-node topology exceeds this budget before cryptographic work.
    limits.nodes = TrieNodeLimit(2)
  of "duplicate":
    # Repeated identities are invalid even with equal payloads.
    return stateTrieRoot(@[source[0], source[0]], limits)
  of "backend-first":
    # Refuse the first attempted primitive call after all resource checks pass.
    fail(1)
  of "backend-late":
    # One complete child and the next value hash precede this refusal.
    failAfter(3)
  else:
    # An unknown selector is a harness error, not rejection evidence.
    quit(2)
  stateTrieRoot(source, limits)

case paramStr(1)
of "root":
  # Failure/default commitments cannot authorize even a default-looking root observation.
  let parsed = rejected(paramStr(2))
  assert parsed.error != StateTrieError.None
  echo array[32, byte](parsed.value.root)[0]
of "entries":
  # Failure/default commitments cannot authorize even a default-looking entries observation.
  let parsed = rejected(paramStr(2))
  assert parsed.error != StateTrieError.None
  echo parsed.value.entries
of "nodes":
  # Failure/default commitments cannot authorize even a default-looking nodes observation.
  let parsed = rejected(paramStr(2))
  assert parsed.error != StateTrieError.None
  echo parsed.value.nodes
of "child-hash":
  # Private recursion must protect its child identity independently from the public commitment wrapper.
  fail(1)
  let source = @[StateEntry(key: default(StateKey), value: @[])]
  let keys = @[KeyIndex(key: default(StateKey), index: 0)]
  let parsed = if paramStr(2) == "default": default(StateTrieResult[StateNodeHash]) else:
    commit(source, keys, 0, 1, 0, ByteLimit(0))
  assert parsed.error != StateTrieError.None
  echo array[32, byte](parsed.value)[0]
else:
  # Unknown observation names are test harness errors.
  quit(2)
