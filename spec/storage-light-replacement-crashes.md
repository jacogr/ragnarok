# Light journal replacement and cleanup process crashes

This clean-room storage qualification covers the standalone local journal format and ownership
contracts in [compaction](storage-light-journal-compaction.md) and
[reclamation](storage-light-journal-reclamation.md). It changes no JAM encoding, trusted root,
compiler/provider pin or application integration boundary.

## Workload and independent observations

Each isolated namespace begins with a genuine selected checkpoint plus an authenticated update
at global sequence one. A retained immutable reader provides the expected proof image. The
replacement candidate independently encodes that image at physical epoch two with an empty
anchored journal and unchanged global sequence. Three related transitions receive grouped
qualification: checkpoint replacement, retirement of epoch one after confirmed replacement,
and discard of a fully staged epoch-two candidate left by an actual rename refusal.

A completed child first establishes each transition's actual successful native operation count.
Every observed write, synchronization, rename, unlink and close boundary used by that transition
is then independently stopped and killed. Replacement also caps real writes at 64 bytes and
kills every completed short chunk, including the final chunks. Unused operation families are
excluded. The parent checks lease contention while the matching child remains stopped, then
requires the exact successful-operation receipt and SIGKILL reap. Normal completion is never
accepted as a killed-boundary verdict.

Forensic expectations are independently authored bytes and bounded prefixes, not output from
production recovery. CURRENT must be exactly the old or new manifest; selected checkpoint and
anchor bytes must be complete. Old file bytes cannot change. For write stops, the control's
actual successful-write ordinal independently predicts each new file's presence and extent.
Cleanup preserves selected files and removes only the intended names in documented order.
Every exact known name and byte is captured before strict reopen and compared afterward.

## Recovery and completion

Fresh strict reopen must preserve the exact forensic namespace and confirm the old or new
selection at sequence one. An explicit candidate-discard retry permits publishing the same
opaque candidate when old CURRENT remains selected. Otherwise an explicit retired-epoch
cleanup retry completes removal, including cases where both names were already absent when
the child died. No cleanup silently supplies selection authority. The next authenticated frame
must append and strictly reopen at global sequence two. Old immutable readers and an independent
unknown sibling remain unchanged. All test-owned children, handles and exact fixture names are
retired explicitly.

Run `make unit SUITE=storage_light_compaction_crashes`. The source-owned evidence file records
actual operation counts, completed controls and killed boundaries. Checked native release
verification retains ARC and bounds checks through the existing Make/Hastur path. This is
process-death evidence on the local filesystem; it does not simulate device power loss or
establish hardware writeback behavior. Exact-head Linux CI remains separate.
