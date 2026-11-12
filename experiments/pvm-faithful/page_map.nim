# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The dynamic-memory page container mirrors Rust 1.99 alloc::collections::BTreeMap:
## B=6, eleven sorted keys per node, linear in-node search, separate leaf/internal
## allocations, parent links and insertion-position-dependent splitting. The tree
## exclusively owns every page allocation. A returned page pointer is a borrow valid
## only until the next insertion, removal or clear. No shared page owner is created.
## Source: Rust library/alloc/src/collections/btree/{node,search}.rs and pinned
## PolkaVM interpreter.rs:829-896. Derived algorithms retain MIT/Apache licensing.

import std/assertions

proc malloc(size: csize_t): nil pointer {.importc, header: "<stdlib.h>", raises: [].}
  ## Obtain the same system-allocator storage class used by the Rust control.

proc free(data: nil pointer) {.importc, header: "<stdlib.h>", raises: [].}
  ## Release raw node or page storage after its initialized children are released.

const Capacity = 11

type
  Page* = object
    ## The tree owns this boxed slice; copies below are explicit ownership transfers.
    data*: nil ptr UncheckedArray[byte]
    length*: int
    readOnly*: bool
  Leaf = object
    ## Rust 1.99 release DWARF: parent=0, values=8, keys=272, parentIndex=316, count=318.
    ## Initialized prefixes only: unused keys/pages are never read or destroyed.
    parent: nil ptr Leaf
    pages: array[Capacity, Page]
    keys: array[Capacity, uint32]
    parentIndex: uint16
    count: uint16
  Internal = object
    ## The leading leaf layout is shared; only internal nodes allocate child edges.
    base: Leaf
    edges: array[Capacity+1, nil ptr Leaf]
  PageMap* = object
    ## Root height distinguishes the allocation layout without a per-node tag.
    root: nil ptr Leaf
    height: int
    count*: int
  PageCursor* = object
    ## Borrowed B-tree range traversal; any structural mutation invalidates it.
    node: nil ptr Leaf
    height, index: int
  Split = object
    ## A newly separated right node and its promoted key/page are still tree-owned.
    present: bool
    key: uint32
    page: Page
    right: nil ptr Leaf
    inserted: nil ptr Page

proc release(root: nil ptr Leaf, treeHeight: int) =
  ## Rust IntoIter drop consumes values in key order, deallocating exhausted nodes on ascent.
  ## Parent edges supply traversal state; there is no recursive walk or extra stack allocation.
  var node = root
  var height = treeHeight
  var index = 0
  if node == nil: return
  while height > 0:
    # Locate the initial leftmost leaf, as the source lazy forward iterator does.
    node = cast[ptr Internal](node).edges[0]
    dec height
  while node != nil:
    if index < int(node.count):
      # Compute the following leaf edge before dropping this key/value pair.
      let page = node.pages[index].data
      inc index
      if height > 0:
        node = cast[ptr Internal](node).edges[index]
        dec height
        while height > 0:
          node = cast[ptr Internal](node).edges[0]
          dec height
        index = 0
      free(page)
    else:
      # Save the parent edge before freeing the exhausted allocation.
      let parent = node.parent
      index = int(node.parentIndex)
      free(node)
      node = parent
      inc height

proc `=destroy`*(tree: PageMap) =
  ## Destroy the entire exclusive tree, accepting an empty moved-from root.
  release(tree.root, tree.height)

proc `=wasMoved`*(tree: var PageMap) {.nodestroy.} =
  ## Transferring the tree leaves a valid empty map.
  tree.root = nil
  tree.height = 0
  tree.count = 0

proc `=copy`*(destination: var PageMap, source: PageMap) {.error.}
  ## A VM memory owner cannot be copied implicitly at a call or assignment.

proc `=dup`*(source: PageMap): PageMap {.error.}
  ## Require an explicit independent capture if a future operation needs cloning.

proc newNode(height: int): ptr Leaf =
  ## Match Rust's distinct leaf/internal allocation sizes and initialized header.
  assert height >= 0
  let size = if height == 0: sizeof(Leaf) else: sizeof(Internal)
  let storage = malloc(csize_t(size))
  assert storage != nil, "faithful B-tree allocation failed"
  let node = cast[ptr Leaf](storage)
  node.parent = nil
  node.parentIndex = 0
  node.count = 0
  node

proc locate(node: ptr Leaf, key: uint32): int {.inline.} =
  ## Rust search.rs:217 uses a linear search within each eleven-key node.
  var index = 0
  while index < int(node.count) and key > node.keys[index]: inc index
  index

proc find*(tree: PageMap, key: uint32): nil ptr Page {.inline.} =
  ## Borrow an existing page without allocating or adjusting a reference count.
  var node = tree.root
  var height = tree.height
  while node != nil:
    let index = locate(node, key)
    if index < int(node.count) and key == node.keys[index]:
      return addr node.pages[index]
    if height == 0: return nil
    node = cast[ptr Internal](node).edges[index]
    dec height
  nil

proc attach(node: ptr Leaf, index: int, child: nil ptr Leaf) =
  ## Set one initialized child edge and repair its raw non-owning parent link.
  assert index >= 0 and index <= Capacity and child != nil
  cast[ptr Internal](node).edges[index] = child
  child.parent = node
  child.parentIndex = uint16(index)

proc insertFit(node: ptr Leaf, height, index: int, key: uint32, page: Page,
    right: nil ptr Leaf): ptr Page =
  ## Shift initialized values once, transferring raw page ownership into the free slot.
  let length = int(node.count)
  assert length < Capacity and index >= 0 and index <= length
  var slot = length
  while slot > index:
    node.keys[slot] = node.keys[slot-1]
    node.pages[slot] = node.pages[slot-1]
    dec slot
  node.keys[index] = key
  node.pages[index] = page
  if height > 0:
    let inner = cast[ptr Internal](node)
    slot = length+1
    while slot > index+1:
      attach(node, slot, inner.edges[slot-1])
      dec slot
    attach(node, index+1, right)
  node.count = uint16(length+1)
  addr node.pages[index]

proc insertOrSplit(node: ptr Leaf, height, index: int, key: uint32, page: Page,
    right: nil ptr Leaf): Split =
  ## Rust node.rs:914 chooses a split based on the new key's insertion edge.
  if int(node.count) < Capacity:
    return Split(present: false, inserted: insertFit(node, height, index, key, page, right))
  let middle = if index < 5: 4 elif index <= 6: 5 else: 6
  let sibling = newNode(height)
  result = Split(present: true, key: node.keys[middle], page: node.pages[middle],
    right: sibling)
  let rightLength = Capacity-middle-1
  for offset in 0..<rightLength:
    sibling.keys[offset] = node.keys[middle+1+offset]
    sibling.pages[offset] = node.pages[middle+1+offset]
  sibling.count = uint16(rightLength)
  if height > 0:
    let inner = cast[ptr Internal](node)
    for offset in 0..rightLength: attach(sibling, offset, inner.edges[middle+1+offset])
  node.count = uint16(middle)
  if index <= middle: result.inserted = insertFit(node, height, index, key, page, right)
  else: result.inserted = insertFit(sibling, height, index-middle-1, key, page, right)

proc insertPage*(tree: var PageMap, key: uint32, size: int, created: var bool): ptr Page =
  ## Return an existing page or allocate one zeroed boxed slice; preserve existing protection.
  assert size > 0
  created = false
  if tree.root == nil: tree.root = newNode(0)
  var current = tree.root
  var height = tree.height
  var edge = 0
  while true:
    # BTreeMap::entry performs one descent and retains the vacant leaf insertion handle.
    assert current != nil
    edge = locate(current, key)
    if edge < int(current.count) and key == current.keys[edge]: return addr current.pages[edge]
    if height == 0: break
    current = cast[ptr Internal](current).edges[edge]
    dec height
  let storage = malloc(csize_t(size))
  assert storage != nil, "faithful page allocation failed"
  zeroMem(storage, size)
  let page = Page(data: cast[ptr UncheckedArray[byte]](storage), length: size, readOnly: false)
  assert current != nil
  var split = insertOrSplit(current, 0, edge, key, page, nil)
  let inserted = split.inserted
  while split.present:
    # Rust insert_recursing ascends the parent links, preserving the inserted leaf handle.
    assert current != nil
    let parent = current.parent
    if parent == nil:
      let newRoot = newNode(tree.height+1)
      attach(newRoot, 0, current)
      discard insertFit(newRoot, tree.height+1, 0, split.key, split.page, split.right)
      tree.root = newRoot
      inc tree.height
      break
    edge = int(current.parentIndex)
    current = parent
    inc height
    split = insertOrSplit(parent, height, edge, split.key, split.page, split.right)
  inc tree.count
  created = true
  assert inserted != nil
  inserted

proc insertPage*(tree: var PageMap, key: uint32, size: int): ptr Page =
  ## The write path does not need to distinguish an occupied entry from a new zero page.
  var created = false
  insertPage(tree, key, size, created)

proc clear*(tree: var PageMap) =
  ## DynamicMemory::reset_memory clears every page and node; it does not retain page snapshots.
  release(tree.root, tree.height)
  tree.root = nil
  tree.height = 0
  tree.count = 0

proc lowerBound*(tree: PageMap, key: uint32): PageCursor =
  ## Find the first key >= the lower bound using one search, as BTreeMap::range does.
  result = default(PageCursor)
  var node = tree.root
  var height = tree.height
  while node != nil:
    let index = locate(node, key)
    if index < int(node.count):
      result = PageCursor(node: node, height: height, index: index)
      if node.keys[index] == key: return
    if height == 0: return
    node = cast[ptr Internal](node).edges[index]
    dec height

proc next*(cursor: var PageCursor, upper: uint32, key: var uint32): nil ptr Page =
  ## Yield one inclusive-range entry and advance along child/parent links without a new search.
  let initial = cursor.node
  if initial == nil: return nil
  let index = cursor.index
  if initial.keys[index] > upper:
    cursor.node = nil
    return nil
  key = initial.keys[index]
  result = addr initial.pages[index]
  if cursor.height > 0:
    # An internal key's successor is the leftmost entry in its right subtree.
    var node = cast[ptr Internal](initial).edges[index+1]
    var height = cursor.height-1
    while height > 0:
      assert node != nil
      node = cast[ptr Internal](node).edges[0]
      dec height
    cursor = PageCursor(node: node, height: 0, index: 0)
  elif index+1 < int(initial.count):
    inc cursor.index
  else:
    # A completed right edge ascends until the first unvisited parent key.
    var node: nil ptr Leaf = initial
    var height = 0
    cursor.node = nil
    while node != nil:
      let parent = node.parent
      if parent == nil: break
      let parentIndex = int(node.parentIndex)
      inc height
      if parentIndex < int(parent.count):
        cursor = PageCursor(node: parent, height: height, index: parentIndex)
        break
      node = parent

proc validateNode(node: ptr Leaf, height: int, low, high: uint64): int =
  ## Diagnostic walk verifies sorted keys, parent links and initialized ownership after mutation.
  let count = int(node.count)
  assert count > 0 and count <= Capacity
  for index in 0..<count:
    assert uint64(node.keys[index]) >= low and uint64(node.keys[index]) < high
    assert node.pages[index].data != nil and node.pages[index].length > 0
    if index > 0: assert node.keys[index-1] < node.keys[index]
  result = count
  if height > 0:
    let inner = cast[ptr Internal](node)
    for index in 0..count:
      let child = inner.edges[index]
      assert child != nil and child.parent == node and int(child.parentIndex) == index
      let first = if index == 0: low else: uint64(node.keys[index-1])+1
      let past = if index == count: high else: uint64(node.keys[index])
      result += validateNode(child, height-1, first, past)

proc validate*(tree: PageMap) =
  ## Run outside measurements; borrowed pages never require this full-map scan during execution.
  assert sizeof(Page) == 24 and sizeof(Leaf) == 320 and sizeof(Internal) == 416
  var probe = default(Leaf)
  let base = cast[uint](addr probe)
  assert cast[uint](addr probe.pages)-base == 8
  assert cast[uint](addr probe.keys)-base == 272
  assert cast[uint](addr probe.parentIndex)-base == 316
  assert cast[uint](addr probe.count)-base == 318
  let root = tree.root
  if root == nil:
    assert tree.count == 0 and tree.height == 0
  else:
    assert root.parent == nil
    assert validateNode(root, tree.height, 0, 0x100000000'u64) == tree.count
