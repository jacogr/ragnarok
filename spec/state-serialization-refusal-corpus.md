# Independently rooted typed serialization refusals

This extends [complete typed serialization evidence](state-complete-serialization-corpus.md)
under Gray Paper pin `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`. No production
codec, authority policy, checkpoint format or runtime integration changes.

Python independently recomputes complete-map roots for sixteen omitted-chapter
maps and sixteen maps with a trailing byte in one chapter. A genuine global-only
control validates all sixteen chapters and an explicitly empty service manifest.
Every fixture first passes raw expected-root restoration and exact checkpoint
re-encoding. Typed restoration must then identify the exact missing chapter or
present malformed chapter with `TrailingBytes`; no root mismatch can stand in
for this typed evidence. A different independently supplied root refuses in the
checkpoint stage for every case, before the semantic stage.

The valid control also distinguishes checkpoint-byte resource refusal, global
chapter-byte refusal and manifest item refusal. Extraction
uses existing guarded reasons and no failure exposes an earlier complete source.
Run `make unit SUITE=state_serialization_refusals`; Python tests reproduce the
SHA-pinned fixture and anchor exact counts, unique roots and trailing-byte labels.
These authored maps do not establish current-pin upstream corpus or STF parity.

Observed locally on macOS ARM64 with pinned checked ARC/Clang release: all 33
native cases, four independent Python checks, source-owned verification inventory
and pinned formatting passed. Exact-head Linux CI remains separate.
