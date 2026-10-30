# JAM network fuzz preset

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, with the explicit
experimental preset proposed in https://github.com/jam-conformance/jam-fuzzing/issues/215.
The conformance protocol remains pinned at `3a488be18fe7b94aa1d35bd0d6f8981ec5bbefae`.
No dependency, historical fixture or protocol encoding pin changes are authorized here.

Scope: accept `JAM_FUZZ_SPEC=fuzz`, require its complete Appendix B tuple, package
central immutable chain presets and explicit host policy, independently calculate complete-map transitions, and
provide a separate Fuzz / JAM Network readiness runner. Live generated campaigns
remain pending a compatible external engine and launcher with explicit fuzz support.

Preset overrides from Full: C85, E60, Y50, R5, K4, block accumulation gas875000000,
refine gas1250000000, preimage expunge900 and lookup age600. All other values retain
Full constants. Initial population255 may resize in multiples of three down to six.
These are validator records; the conformance target imports engine-authored blocks
through its Unix socket without starting a multi-node QUIC network or slot timer.

Completion checks: strict startup/profile refusal; independent before-launch blocks
and full maps at ordinary/skipped epoch boundaries and delayed population activation;
real socket queries and import comparisons; packaging/runner failure and pending-engine
controls. Preserve missing child-root evidence as a local refusal and all GP checks.
The pinned Initialize ancestry encoding has at most24 records; lookup age600 does
not authorize changing that wire limit or inventing missing headers.

## Delivered readiness scope

The complete new preset tuple and policy-owned consensus constants are checked at
startup, including lookup age600, rotation5, tail50, ticket cap4 and block gas875000000.
The bundled candidate policy retains601 header facts under16MiB and the standard
24-record Initialize wire cap. Existing Tiny/Full startup behavior and fixture pins
remain unchanged. The ordinary binary selects conformance mode from the five
upstream target environment variables, without required arguments, policy files
or working-directory assumptions. Embedded host policy derives profile-dependent
fields from the canonical Tiny/Full/Fuzz catalog. The Docker preset inherits the
ordinary entry point and needs no custom Fuzz arguments or shell adapter.
Legacy explicit-policy commands remain for internal regression compatibility.


Seventeen independently authored sessions contain67 imports:20 epoch/population maps,
12 nonempty guest/sibling maps and35 expiry/rollback maps. Distinct Bandersnatch/Ed25519 identities, genuine
guarantees at core84 and171/172 authenticated assurance votes exercise admission and
storage/yield, rollback and checkpoint retention. Public-scalar points, signatures,
headers and complete successors are calculated independently before native startup.
Only255-capacity KZG roots are attributed primitive inputs. Full references gain
explicit geometry arguments with unchanged default values and historical pins.

The dedicated Fuzz / JAM Network task owns `make check-jam-network`, native corpus
comparison and actual packaged-entry socket replay. Its aggregate requires all17
sessions,67 valid imports,67 consensus refusals,171 complete-state queries, three
retained sibling maps and reconnect isolation. Live engine/campaign status stays
pending in results and summary. Container build and live engine validation are
separate from macOS native/entry-point readiness evidence.

Environment-only ordinary-binary replay requires missing variables and extra
arguments to fail before creating directories. It starts from an owned0777 socket
directory, creates nested data directories natively and verifies all67 imports,
171 queries and67 atomic refusals with graceful SIGTERM cleanup. Native startup
checks validate built-in defaults for Tiny, Full and Fuzz. Historical Full
profile/guest/epoch and derived-expiry corpora retain their80-import qualification
and unchanged pins. Exact published-head Linux CI has its own verdict.

Remaining campaign work: compatible engine distribution and a fuzz-aware upstream
launcher, then bounded known campaigns with generated traces and explicit completion
accounting. New-preset disputes and ticket contests
can extend this source-owned plan; existing Tiny/Full coverage remains unchanged.

Upstream `scripts/target.py` creates the explicit host runtime directory with0777.
The binary verifies that each selected data/socket directory belongs to the
effective runtime user and tightens it to0700 before opening the socket. Rootful Docker
uses the launcher's host UID; the dedicated stage defaults to container root for
the rootless host-owner mapping. Native private-directory and inode cleanup checks
remain unchanged. Actual entry-point replay starts from the upstream0777 mode.

## Explicit Fuzz expiry and central parameters

The pinned GP `text/pvm_invocations.tex` lines60–62 defines D=L+4800. Issue215
specifies D900 with L600. The maintainer explicitly authorized D900 for Fuzz;
Tiny/Full/custom configurations preserve their existing derived expiry semantics.
`src/chain/presets.nim` owns every canonical Tiny/Full/Fuzz scalar. Startup selects
that immutable preset once, validates duplicated policy consensus limits against it,
and retains explicit-expiry interpretation in each snapshot. Resource limits remain
separate. The fetch tuple stays122 bytes; profile equality includes interpretation.
Durable V1 checkpoint capture refuses explicit-expiry profiles because that schema
cannot retain the interpretation; this target remains ephemeral.

Ten independently calculated expiry sessions start at slot929 with removal slot32.
Release at932 retains the removed history; at933 it deletes the preimage and its
82-byte/two-item reservation. Restoration compacts history without releasing storage;
live requests, panic rollback and checkpoint-then-panic retain their exact respective
maps. All expected signatures, gas and complete maps precede native execution.
Historical Full and preimage-aging references retain their original pins and defaults.
