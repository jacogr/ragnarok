# Shared preparation before candidate handoff

The previous report documentation/profile label confused the six tiny validators with the two
tiny cores. The pinned vector README is authoritative for those profile parameters. Native report
range checking already accepts an explicit bound and is unchanged. The standalone tiny codec
report's core index is 3, so its byte-exact test uses a permissive bound and a separate two-core
rejection check now covers actual tiny eligibility. Historical work-report metrics remain intact.
This is a confirmed shared specification/test-labelling defect found by review, not a decoder
failure or evidence of a language-specific reliability difference.

The assurances contract, independent Python oracle and protocol driver harness are prepared before
any candidate handoff. Native order is Mojo, Nim, Odin, counterbalancing the previous Odin, Mojo, Nim
round. Each candidate will finish implementation and all registered checks before the next begins.
No new speed experiment is part of this increment; Nim still builds checked ARC/Clang LTO.

Reusable Nim/Mojo type and helper sources were also inspected before some candidate handoffs.
This was shared preparation, but comparative latency is conservatively N/A; raw journal intervals
remain available. New candidate source edits and direct compiler attempts began after registration.
Later shared-tool changes added explanatory comments and separate oracle/type integrity checks;
the request corpus and expected behavior remained identical, confirmed against every acceptance hash.
Mojo's first direct successful source compile could not emit its binary because shared setup had
not created build/assurances. The unchanged retry and infrastructure attribution are preserved.
