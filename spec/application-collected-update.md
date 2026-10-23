# Shared current collection admission

`captureCollectedUpdate` is the common host gate for opaque native current completions. It preserves
receipt lifecycle, typed receiver refusal and exact physical prior/full-view admission. A receipt
remains an observation; canonical adoption makes it stale on that chain without altering another
independent immutable-parent branch. This gate does not release any worker lease and must only
run after matching collection/join. Identity-preserving qualification delegates to the same gate.
The native application_collected_update suite checks actual receipts, absent and adopted chains,
unchanged alternate branches and original posterior source identity.
