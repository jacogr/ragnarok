# Current command remote original-history acquisition

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains primary. This layer
qualifies current-command acquisition through existing bounded authenticated ancestor transport,
with no new protocol interpretation, implementation or dependency change.

An independently composed signed two-guarantee child needs a genuine original-history lookup.
Up-front acquisition must request the exact original head's parent in descending direction before
requesting the child. Child-driven discovery must first receive the child and collect its actual
missing-lookup demand, gracefully retire its endpoint, fetch the original header, then resume the
same input without downloading the child again. The policy explicitly selects the matching mode.

Eight native command-API cases cover both modes: journal and managed successful adoption with
strict complete-map reopen, wrong sealed-parent identity, and missing FIN until the original
whole-command deadline. An independent forked TLS responder checks every request byte and count;
all Services/worker ownership ends before process reaping and restart. Refusals must preserve an
already seeded journal byte-for-byte, zero adopted progress and the complete original canonical map.
Expected acquired headers provide lineage only; they never create current completion authority.

Run `make unit SUITE=pvm_current_download_remote`. All eight native cases, focused semantic checking, inventory and pinned formatting passed locally
on macOS.
These are actual command API/TLS witnesses, separate from the executable cases in
`pvm-current-download-executable.md`; two successful consecutive current children, exhaustive
scheduling, Linux CI, full state serialization and full JAM/ThinVRF parity remain outside this layer.
