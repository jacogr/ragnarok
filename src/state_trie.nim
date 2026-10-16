## GP 0.8.0 merklization: bounded roots over already serialized state entries.
## Inputs are borrowed synchronously and must remain stable for the call. Nothing is retained.
import std/algorithm
import ./[state_layout, bounded]

type
  ## A serialized mapping entry; callers own the value and retain its lifetime during construction.
  StateEntry* = object
    key*: StateKey
    value*: seq[byte]
  ## A complete trie root, distinct from internal node identities and partial commitments.
  StateRoot* = distinct array[32, byte]
  ## Maximum number of nonempty leaf/branch nodes hashed during a call.
  TrieNodeLimit* = distinct uint64
  ## Independent ceilings bound entries, individual/aggregate value bytes and trie topology.
  StateTrieLimits* = object
    items*: ElementLimit
    perValue*, totalValueBytes*: ByteLimit
    nodes*: TrieNodeLimit
  ## Default and failed results carry no root, count or intermediate progress.
  StateTrieError* {.pure.} = enum
    Uninitialized, None, LimitExceeded, DuplicateKey, LengthOverflow, BackendFailure
  ## A completed root and exact number of entries/nonempty nodes committed.
  StateTrieCommitment* = object
    root*: StateRoot
    entries*: int
    nodes*: uint64
  ## Only a successful alternative exposes a completed commitment.
  StateTrieResult*[T] = object
    case error*: StateTrieError
    of StateTrieError.None:
      value*: T # Only complete success exposes root/count metadata.
    else:
      discard   # Default and failures contain their reason alone.
  ## Private copied keys and source indices avoid retaining or copying caller values during sorting.
  KeyIndex = object
    key: StateKey
    index: int

## Compare fixed keys lexicographically, which agrees with MSB-first bit order.
proc compare(a, b: KeyIndex): int =
  let left = array[31, byte](a.key)
  let right = array[31, byte](b.key)
  # Stop at the first differing octet; equal keys are rejected before topology traversal.
  for i in 0..<31:
    if left[i] < right[i]: return -1 # Earlier zero bits belong to the left subtree.
    elif left[i] > right[i]: return 1 # Later one bits belong to the right subtree.
  0

## Locate the zero/one partition within a sorted range sharing all preceding key bits.
proc split(keys: seq[KeyIndex], first, stop, depth: int): int =
  var lo = first
  var hi = stop
  # Binary search avoids rescanning long shared prefixes and uses overflow-safe midpoint arithmetic.
  while lo < hi:
    let mid = lo + (hi-lo) div 2
    let key = array[31, byte](keys[mid].key)
    if (key[depth div 8] and byte(128 shr (depth mod 8))) == 0:
      lo = mid+1 # Zero-bit entries precede the split.
    else:
      hi = mid # One-bit entries follow the split.
  lo

## Preflight exact topology before cryptographic work; unary branches are real committed nodes.
proc countNodes(keys: seq[KeyIndex], first, stop, depth: int,
                limit: TrieNodeLimit, used: var uint64): StateTrieError =
  if first == stop: return StateTrieError.None # Empty children are zero hashes, not nodes.
  if used >= uint64(limit): return StateTrieError.LimitExceeded # Check before increment, including uint64 maximum.
  inc used
  if stop-first == 1: return StateTrieError.None # A singleton is a leaf at any depth.
  if depth >= 248: return StateTrieError.DuplicateKey # Defend the full fixed-key domain before access.
  let middle = split(keys, first, stop, depth)
  let left = countNodes(keys, first, middle, depth+1, limit, used)
  if left != StateTrieError.None: return left # Stop without hashing after a resource failure.
  countNodes(keys, middle, stop, depth+1, limit, used)

## Hash the preflighted topology using canonical raw node encodings and complete child identities.
proc commit(entries: openArray[StateEntry], keys: seq[KeyIndex], first, stop, depth: int,
            perValue: ByteLimit): StateTrieResult[StateNodeHash] =
  if first == stop:
    # The empty dictionary identity is all zeroes, never Blake2b(empty).
    return StateTrieResult[StateNodeHash](error: StateTrieError.None, value: StateNodeHash(default(
        array[32, byte])))
  var encoded: EncodedStateNode
  if stop-first == 1:
    # Leaf encoding selects inline versus raw-value hashing at the exact 32/33-byte boundary.
    let leaf = encodeStateLeaf(keys[first].key, entries[keys[first].index].value, perValue)
    if leaf.error != StateLayoutError.None:
      return StateTrieResult[StateNodeHash](error: StateTrieError.BackendFailure) # Preflight already ruled out policy failure.
    encoded = leaf.value
  else:
    # Preserve every shared-prefix branch and its empty sibling rather than compressing paths.
    let middle = split(keys, first, stop, depth)
    let left = commit(entries, keys, first, middle, depth+1, perValue)
    if left.error != StateTrieError.None: return left # Failed children expose no identity.
    let right = commit(entries, keys, middle, stop, depth+1, perValue)
    if right.error != StateTrieError.None: return right # Do not publish a partially constructed branch.
    encoded = encodeStateBranch(left.value, right.value)
  let hashed = hashStateNode(encoded)
  if hashed.error != StateLayoutError.None:
    return StateTrieResult[StateNodeHash](error: StateTrieError.BackendFailure) # Foreign primitive failure cannot become a zero root.
  StateTrieResult[StateNodeHash](error: StateTrieError.None, value: hashed.value)

## Compute an order-independent root without mutating inputs. All duplicate keys are rejected.
## O(n) private key/index sorting scratch and at most 248 recursive branch levels are released by ARC.
## Values remain borrowed; allocation exhaustion follows the project's Nim fail-stop allocation policy.
proc stateTrieRoot*(entries: openArray[StateEntry], limits: StateTrieLimits): StateTrieResult[
    StateTrieCommitment] =
  if uint64(entries.len) > uint64(limits.items):
    return StateTrieResult[StateTrieCommitment](error: StateTrieError.LimitExceeded) # Bound input-derived scratch first.
  if entries.len > high(int) div sizeof(KeyIndex) or entries.len > high(int) div sizeof(StateEntry):
    return StateTrieResult[StateTrieCommitment](error: StateTrieError.LengthOverflow) # Typed extents must fit native addressing.
  var total = 0'u64
  # Validate every payload before scratch allocation or any cryptographic operation.
  for entry in entries:
    let size = uint64(entry.value.len)
    if size > uint64(limits.perValue) or size > uint64(limits.totalValueBytes)-total:
      return StateTrieResult[StateTrieCommitment](
          error: StateTrieError.LimitExceeded) # Subtraction prevents aggregate overflow.
    total += size
  var keys = newSeq[KeyIndex](entries.len)
  # Copy only fixed keys and indices; source order and backing value storage stay untouched.
  for i, entry in entries: keys[i] = KeyIndex(key: entry.key, index: i)
  keys.sort(compare)
  # Duplicate rejection is independent of payload equality and prevents ambiguous last-value-wins behavior.
  for i in 1..<keys.len:
    if compare(keys[i-1], keys[i]) == 0:
      return StateTrieResult[StateTrieCommitment](
          error: StateTrieError.DuplicateKey) # A mapping cannot contain repeated identities.
  var nodes = 0'u64
  let counted = countNodes(keys, 0, keys.len, 0, limits.nodes, nodes)
  if counted != StateTrieError.None:
    return StateTrieResult[StateTrieCommitment](error: counted) # No root or progress escapes resource preflight.
  let hashed = commit(entries, keys, 0, keys.len, 0, limits.perValue)
  if hashed.error != StateTrieError.None:
    return StateTrieResult[StateTrieCommitment](error: hashed.error) # Propagate only the failure reason.
  StateTrieResult[StateTrieCommitment](error: StateTrieError.None,
    value: StateTrieCommitment(root: StateRoot(array[32, byte](hashed.value)), entries: entries.len, nodes: nodes))
