# Current state and chain-view coordinator

Accept one genuine current consensus-composed successor. Require the live
StateStore and ChainView selected head to retain its exact original admitted
parent snapshot; compare core, epoch and validator profiles plus every field of
the exact parameter tuple frozen for execution before capture. A different
price/fetch field with matching core/epoch counts still refuses as a profile mismatch.
Derive sealed header from the same current source, bound its complete byte
extent, privately adopt the already composed state, capture the child with the
retained chain parameters and advance a private view. Run no guests or composition
again. Replace both live handles only after every fallible step succeeds, with
no callbacks or fallible work between the two single-threaded assignments.

Failures preserve exact original state/view identity, selected head, finality
and parameters. Keep typed source/state/view/profile/header/capture/publication
refusals and expose no earlier successful prefix. Equal-root or earlier-source
versions cannot replace parent identity. Retained aliases remain historical.
The Gray Paper pin remains `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`;
this coordinator adds ownership/publication behavior, not protocol interpretation.

Completion witnesses: compare explicit private adoption/header capture/direct
append with the coordinator; exact state/view child identity; wrong state/view/
profile/default/replay and late capture/append refusals; bounded header bytes;
no re-execution; alias/finality retention and ARC. Durable preparation/install
and full JAM parity remain separate work.

Local macOS ARC/Clang checks passed: 303 source modules; current coordinator/
publication and legacy coordinator native suites; seven runtime probes and five
privacy/nominal compiler rejections; fresh 1,000-cycle ARC evidence; inventory and
formatting. Linked native/runtime checks ran serially. Linux CI and full JAM
parity remain separate evidence.
