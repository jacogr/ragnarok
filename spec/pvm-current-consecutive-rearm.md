# Refused current rearming preserves the consumed adoption receipt

After a genuine first adoption, regressing the clock, exceeding the ancestor count, supplying a
malformed header or exceeding the explicit ancestor-byte budget each refuses before discarding
the old result or changing canonical state. A later valid empty-context rearm performs no IO by
itself, rejects another rearm while waiting, then genuinely downloads and adopts the second child.
Memory, journal and managed cases preserve exact request counts and all strictly reopened history.

Run `make unit SUITE=pvm_current_consecutive_rearm`. Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains primary. No runtime/default policy changes;
these authored implemented-scope witnesses do not claim upstream full STF/Thin VRF parity.
M1 framing remains separate from full typed state serialization.
