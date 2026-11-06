# ark-vrf 0.6.2 qualification

The primitive dependency advances from 0.6.1
`cf1dbbb260ec3e7ea88eac68148f05d5cbd587ac` to
`439242a5bf3a142e720cb907fb39d134f1d09192`. The locked package graph changes only
the ark-vrf version. The upstream release rejects unchecked off-curve inputs to
Tiny and Thin verification, bounds ring setup by available SRS capacity before
domain arithmetic, and rejects malformed SRS lookup lengths.

Ragnarok's bridge decodes canonical inputs with curve and subgroup validation,
rejects identities where required and bounds requested capacities before setup.
It uses the embedded public ceremony SRS and does not expose an SRS lookup
callback. This update strengthens the dependency without identifying an exposed
unchecked bridge path. The upstream off-curve, capacity, domain overflow and
lookup regression tests passed in a separate checkout of the release.

The maintained profile stays Draft 35 Thin v1, with the existing 16-byte
challenge, 96-byte ordinary signature and 784-byte ring proof. The native
corpus retains the seven Draft 35 Thin and seven Draft 35 domain-512 ring
vectors, the official Tiny/Full JAM tickets and the invalid-input ABI checks.
The seven new upstream v1 ring vectors use domain 2048 even though their
member list contains eight keys. The compatibility check uses the existing
Full setup request (1,023 members) to select domain 2048. It reproduces each
144-byte commitment and verifies each proof and output there, and rejects
the same proof at domain 512. Both 0.6.1 and 0.6.2 agree with the fixtures
at matching domains; neither v2 nor a domain policy change is needed.

Both pin manifests record the new lock digest. The six frozen input provenance
records and their dependent fingerprints follow the updated pin file, without
changing cryptographic payloads, historical fixture bytes or state outputs.
The vector source pin is independent of this update.
