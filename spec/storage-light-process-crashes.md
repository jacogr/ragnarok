# Light-file process-crash qualification

This grouped native qualification covers the existing complete-image light publication path before
introducing incremental persistence. It changes no production format, trust selection or durability
receipt. Independently trusted chain/root arguments, immutable readers and separate full/light
schemas retain their contracts. Application/startup integration remains gated; M1 framing does
not establish full state serialization or JAM client completion.

A complete independently hashed two-key fixture retains long/empty presence. One atomic combined
update forgets the long value and adds an authenticated absent query at the same complete root.
Independent full preparation fixes exact old/new canonical images. Each scenario initializes a
private namespace, retains an old reader, closes the parent writer and forks one supervised child.
The child strictly opens before arming observation, then performs the real combined update.

Successful controls count actual write, staged-file sync, staged close, rename and directory-sync
boundaries. A separate control caps genuine write progress at64 bytes. Every observed successful
call becomes an independent stop/kill scenario. Before killing, the parent requires the exact
observer stop receipt and proves a second owner cannot steal the stopped child's LOCK. Exact-child
SIGKILL/reap receipts distinguish process death from completed controls, unmarked stops, early
exits or deadlines. Existing supervision negative controls run alongside the feature suite.

Writes, file sync and staged close leave old CURRENT selected. Rename and directory sync expose
exactly the new image. Every interrupted short write leaves exactly its authored candidate prefix;
the final complete write is still unselected before rename. Strict reopen verifies the selected
proofs against the independent root and preserves both CURRENT and every remaining staging byte.
Removed presence becomes locally unknown; retained authenticated absence stays an explicit Absent
result only in the selected new image. No partial cache revision is authorized.

Explicit pending cleanup may remove only the regular unselected CURRENT.next after revalidating
CURRENT. A deliberately unrelated KEEP file survives cleanup and retry. Publication/reopen then
selects the independent new image. The retained old reader preserves its original presence/unknown
knowledge after every child and writer retires. Exact test-owned files are removed only after
all locks, descriptors and child ownership have been retired.

## Local verification

The checked native light suite passes five completed controls and thirteen independently witnessed
kills, including all eight real64-byte write chunks, both sync boundaries, staged close and rename.
Every killed-child case proves live lease contention, exact selected/staged bytes, strict reopening,
forensic preservation, explicit cleanup, retry and retained reader semantics. The maintained
supervision control suite also passes its invalid-hook, unmarked-stop, early-exit, timeout and
cancellation cases. Semantic checking, formatting and verification inventory pass.

These are process-death observations on the local filesystem. They do not simulate physical
power loss, dropped drive caches, kernel failure, cold-cache storage or exact-head Linux CI.
