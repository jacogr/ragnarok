# Protocol-parameter fetch

Scope: fetch selector 0 returns the configured chain's fixed 122-byte protocol-parameter
tuple. Normative source: Gray Paper 0.8.0, gitlink
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm_invocations.tex`, General
Functions, Omega_Y selector 0; `text/definitions.tex`, CgasYc/CgasYl entry 0 and the
29 referenced parameter definitions. Field order and E2/E4/E8 widths follow the tuple
exactly. There is no count prefix and no compact encoding. Cost is always 390,
independent of requested length, clipping or item registers r11/r12.

The existing chain Parameters snapshot already decodes this exact tuple from explicit
configuration. encodeParameters now re-emits it using the same private field-width
map; valid exposes the decoder's existing population/clock checks and rejects the
default snapshot. The encoder requires a valid snapshot. Private fields originate
only from fixed-width decoding, so re-encoding cannot truncate an oversized scalar.
This does not add chain-profile validation or infer validator-dependent settings.
Invocation assembly must keep this snapshot consistent with the configuration used
by the other host/state components; attaching it does not reconfigure their limits.

withFetchParameters rejects invalid context/default parameters with InvalidContext,
then copies the fixed encoding into a private acyclic owner. No variable byte budget
is needed for this 122-byte field. FetchContext capture without parameters remains
usable for other selectors; calling selector 0 before parameters are attached is a
local InvalidContext refusal, never NONE or a fabricated default network profile.
A complete invocation caller must attach its chain's configured Parameters. There is
no implicit hard-coded full or tiny profile. Alternate valid configured tuples are
returned verbatim. Parameter replacement and package/input attachment or clearing
preserve unrelated snapshots and retained handles.

Normal fetch semantics apply: funded r7 reports the full 122-byte length, offsets and
requested lengths clip to the selected suffix, natural empty copies allow arbitrary
pointers, insufficient gas takes precedence over copy faults/caps, and a nonempty
unwritable range panics atomically. Local copy-policy refusals carry no partial host
response. Missing configuration remains local even if guest gas would be insufficient.

Independent tests contain all 29 pinned GP values and their literal little-endian
bytes, plus a distinct small profile and every field at its maximum encoded width.
Tests cover truncated/extended tuples, the unchanged clock/population validation,
source mutation, attachment ordering, retained handles, ignored indices, full-width
requests/offsets, exact/short gas, memory faults, local caps, real host-loop dispatch
and 1,000 fresh ARC cycles. Runtime probes reject capture/refusal payload extraction
and invalid encoder calls; a compiler guard protects the parameter owner. Existing
RPC parameter tests exercise the shared decoder's consumers. No upstream source or
vectors are copied.

Fetch selectors 0–13 are implemented with explicit configuration where required.
Remaining: accumulation-input selectors 14–15, complete invocation assembly and the
existing positive gas-domain gate. Next bounded increment: accumulation-input capture
and canonical fetch encoding, using the existing accumulation operand types.
