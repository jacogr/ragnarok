# Paired interpreted measurement and rejected register-run trial

## Measurement contract

The ordinary PVM application cohort compares the current explicit interpreter with a previous
JIT policy, so it cannot attribute an interpreter-only change. The opt-in
`pvm_interpreter_pair` workflow input requires a full `pvm_prepared_baseline` commit SHA. It
builds a baseline explicit interpreter and baseline JIT from the same archived source with
identical compiler flags, and requires equal executable images. The candidate interpreted and
JIT roles likewise share source and images. All six roles run the same frozen fixtures, positive
and refusal controls, thirteen checked calls per process and both process orders. Interpreter
policy and owner receipts must report zero native activity. The ordinary five-role cohort stays
available without the opt-in input.

The paired mode was qualified by [ARM run 41097353591](https://github.com/jacogr/ragnarok/actions/runs/41097353591)
at candidate `7043e4f78aed883e667f8b8f9652b8f2a1a61a7d` against exact master
`4a29188758026f062e2b970b96df2665d8764d4e`, pinned Nimony
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`, checked release/ARC/Clang ThinLTO, on one
Linux ARM64 runner. Its `tests/pvm-arm64-applications/results.json` SHA-256 is
`eb792d5f4cc304850b49439e9aa5a8bdff0016b7a73e02524b732b0e5f0f9fee`. The sealed report
passed 20 fresh builds, 84 measured processes, 138 positive/refusal controls, equal images for
each policy pair, and complete CPU/register/gas/page/source and ordered host-event checks. The
separate JIT profile is diagnostic; its instrumented clocks are not benchmark timings.

## Rejected register-run experiment

The measured candidate batched four or more consecutive register-only operations in an explicit
interpreted plan. Each interior node remained addressable for direct entry and partial attempt
barriers; the default JIT scanner retained its handler identities. A literal six-operation unit
compared the candidate with the default policy across source budgets, paid/unpaid gas and
reordered entries. Local ARM feedback on sieve 100,000 showed candidate/baseline ratios
0.987/0.981, but a non-timed full-state diagnostic found only 491 run entries and 2,769 covered
register operations among 1,166,742 source attempts per call. The local timing difference was
too small and the path too rare to establish a useful dispatch saving.

The paired CI result is decisive for the real application. Warm public CPU medians below are
milliseconds; each row uses one process order and the same runner, inputs and reference.
`Interpreted / PolkaVM` is raw public invocation time divided by PolkaVM interpreted call time.
JIT is a separately labeled unchanged-policy control.

| DOOM phase / order | Previous interpreted | Candidate interpreted | PolkaVM interpreted | Candidate / previous | Previous / PolkaVM | Candidate / PolkaVM | Previous JIT | Candidate JIT |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| init / forward | 532.457 | 523.861 | 623.798 | 0.984 | 0.854 | 0.840 | 323.605 | 322.315 |
| init / reverse | 508.549 | 518.146 | 627.910 | 1.019 | 0.810 | 0.825 | 310.325 | 306.576 |
| tick / forward | 48.324 | 49.211 | 40.055 | 1.018 | 1.206 | 1.229 | 40.576 | 40.478 |
| tick / reverse | 48.408 | 49.251 | 40.018 | 1.017 | 1.210 | 1.231 | 40.688 | 40.486 |

DOOM tick regressed 1.8%/1.7% in both orders, and init changed direction between orders.
Pinky regressed 2.9%/3.2%; minimal, memset and sieve showed mixed or flat results. The small
local sieve result did not transfer to the full runner. There was no justified broader gain, so
the register-run handler and its trial-only unit were removed. The final PR retains only the
paired measurement capability and this rejection evidence. No performance claim is made for the
measurement tooling itself.

## Next execution lead

A separate non-timed, full-state and ordered-event checked DOOM tick diagnostic found no connected
ARM region calls. Its hottest charged block at byte PC 530670 contains register opcode 198,
indirect store 120, registers 149/149 and conditional branch 171. The native suffix starts after
the checked store, then returns to the block header 767,998 times and exits 256,000 times in one
invocation. A one-block pure-register region or more slots alone cannot connect that loop; any
general region change must preserve store fault, dirty-page, gas, attempt and PC behavior. This
diagnostic guides later work and contributes no timing to the rejection above.
