# ARM self-loop trial: rejected

[Run40712609291](https://github.com/jacogr/ragnarok/actions/runs/40712609291) at measured head
`5ba781f7cfb65eaf0a2e3616ed5729565820e2b9` compares the trial to accepted parent
`f45793f6bfe92d38488b52898652e5dfb49ddbdb` on native Linux ARM64, using pinned October26
Nimony358b9bce / checked release / ARC / Clang ThinLTO. Native/refused boundary qualification
passes, including1920 new ordinary/specialized-header one-block source comparisons. The full
application cohort passes70 processes /910 checked calls,115 controls,16 private fresh builds /
eight equal-image pairs. Independent audits verify745 source/input/compiler/image identities,
reparse raw logs and retain full state/gas/pages/permissions/source/ordered-host-event checks.
Report SHA256: `1e9cb5a1471eb29e5b745de218e2f0ba95dcaa0421a55c9a0fe4836716219f8a`.

Reject the runtime: DOOM initialization regresses from331.623/327.174 to543.488/539.974ms
(about64–65%), including retained-core slowdown. Source attempts are identical. Native lowered
operations across13 calls collapse from about2.27b to57,336,599, and publications change1024 to1023.
The results are consistent with an earlier self-loop occupying the single source-owned region
slot and displacing the previously useful larger region; they do not isolate every CPU cause.
Sieve timings move3–5% favorably, but its native activity is identical, so that movement is not
claimed as a connected-self-loop gain. Pinky and gameplay move within small percentages.

Restore both ARM runtime files exactly from the immediate accepted experimental parent, which
retains the accepted x86 trial. Preserve the paired ARM baseline support, strict complete-case
receipt tests, all1920 independent state cases and explicit refusal of both one-block shapes.
The maintainer-approved logical-block normalization of scalar control evidence remains valid
for existing multi-block regions; complete state assertions are unchanged. No public default,
pricing, host, memory or dependency change remains in this layer.

Next bounded direction: region selection/lifetime needs measured hotness or separate capacity
before adding shapes. A new loop must not silently displace an established better region.
Register retention is already present in ARM regions; background compilation would not resolve
this selection failure. No follow-on runtime optimization is mixed into the rejection evidence.

Full measured tables follow; values are from the rejected head, not post-restoration results.

CPU ms, forward / reverse. Public calls include fresh invocation memory and immutable publication; core has separate reset/publication.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.485 / 3.499 | 2.981 / 2.982 | 2.837 / 2.878 | 2.684 / 2.680 | 6.077 / 6.090 | 0.814 / 0.823 | 0.467 / 0.473 |
| minimal 100000 | 6.277 / 6.157 | 5.860 / 5.887 | 5.883 / 5.898 | 6.057 / 6.028 | 5.524 / 5.548 | 0.937 / 0.958 | 1.065 / 1.063 |
| memset 100000 | 4.579 / 4.382 | 4.448 / 4.422 | 4.590 / 4.444 | 3.647 / 3.632 | 3.725 / 3.724 | 1.002 / 1.014 | 1.232 / 1.193 |
| pinky 1 | 95.291 / 95.659 | 86.819 / 87.009 | 86.493 / 86.862 | 86.995 / 87.181 | 87.844 / 87.912 | 0.908 / 0.908 | 0.985 / 0.988 |
| sieve 10000000 | 343.987 / 345.590 | 287.883 / 286.186 | 274.009 / 274.458 | 280.233 / 279.594 | 332.966 / 333.973 | 0.797 / 0.794 | 0.823 / 0.822 |
| init 0 | 536.177 / 535.960 | 331.623 / 327.174 | 543.488 / 539.974 | 553.063 / 536.354 | 624.157 / 627.742 | 1.014 / 1.007 | 0.871 / 0.860 |
| tick 0 | 49.243 / 49.152 | 46.820 / 47.085 | 46.374 / 46.498 | 41.023 / 40.757 | 40.078 / 40.081 | 0.942 / 0.946 | 1.157 / 1.160 |

All following CPU values are milliseconds, forward / reverse. Constructors and cold calls are separate from reused calls.

Public owner construction and cold sample zero

| Case | Interpreter owner | Previous owner | Current owner | Interpreter cold | Previous cold | Current cold | Reference cold call |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 2.854 / 3.041 | 2.848 / 3.016 | 2.835 / 3.052 | 8.906 / 8.935 | 10.438 / 10.592 | 10.345 / 10.545 | 6.459 / 6.212 |
| minimal 100000 | 0.013 / 0.018 | 0.015 / 0.014 | 0.015 / 0.015 | 6.438 / 6.270 | 6.105 / 6.075 | 6.086 / 6.101 | 5.596 / 5.610 |
| memset 100000 | 0.057 / 0.054 | 0.056 / 0.066 | 0.057 / 0.057 | 8.676 / 7.790 | 8.510 / 8.661 | 8.744 / 8.249 | 3.824 / 3.820 |
| pinky 1 | 0.750 / 0.716 | 0.713 / 0.717 | 0.721 / 0.746 | 97.871 / 98.145 | 91.011 / 91.172 | 90.494 / 91.055 | 87.881 / 87.935 |
| sieve 10000000 | 3.048 / 3.039 | 3.051 / 3.221 | 3.017 / 2.980 | 350.643 / 351.106 | 296.536 / 295.621 | 282.259 / 282.578 | 333.354 / 334.262 |
| init 0 | 8.476 / 8.561 | 8.604 / 8.596 | 8.637 / 8.572 | 548.679 / 553.343 | 360.623 / 352.043 | 566.224 / 553.882 | 629.207 / 626.695 |
| tick 0 | 8.526 / 8.602 | 8.581 / 8.567 | 8.591 / 8.528 | 64.487 / 64.891 | 64.488 / 64.909 | 64.675 / 64.054 | 40.346 / 40.337 |

Retained core construction and reused lifecycle; these are not public-call ratios

| Case | Facts constructor | Memory/frame constructor | Reused reset | Reused call | Reused publication | Reused total |
|---|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 2.616 / 2.696 | 0.525 / 0.549 | 0.047 / 0.048 | 2.684 / 2.680 | 0.016 / 0.015 | 2.748 / 2.745 |
| minimal 100000 | 0.012 / 0.012 | 0.070 / 0.068 | 0.002 / 0.002 | 6.057 / 6.028 | 0.002 / 0.002 | 6.060 / 6.032 |
| memset 100000 | 0.055 / 0.053 | 3.451 / 2.966 | 0.279 / 0.205 | 3.647 / 3.632 | 0.081 / 0.063 | 4.010 / 3.900 |
| pinky 1 | 0.891 / 0.813 | 0.392 / 0.394 | 0.032 / 0.031 | 86.995 / 87.181 | 0.150 / 0.150 | 87.184 / 87.366 |
| sieve 10000000 | 2.764 / 2.641 | 0.504 / 0.536 | 0.059 / 0.054 | 280.233 / 279.594 | 0.286 / 0.295 | 280.576 / 279.942 |
| init 0 | 8.622 / 8.669 | 14.049 / 13.977 | 7.021 / 6.771 | 553.063 / 536.354 | 0.037 / 0.033 | 559.876 / 543.097 |
| tick 0 | 8.697 / 8.826 | 14.100 / 14.938 | 6.408 / 5.987 | 41.023 / 40.757 | 0.040 / 0.034 | 47.438 / 46.789 |

Reference DOOM invocation lifecycle; module construction remains separate

| Case | Restore | Call | Teardown | Total |
|---|---:|---:|---:|---:|
| init | 2.515 / 2.509 | 624.157 / 627.742 | 0.186 / 0.255 | 626.856 / 630.410 |
| tick | 2.567 / 2.560 | 40.078 / 40.081 | 0.153 / 0.144 | 42.811 / 42.810 |

Current public native totals across all thirteen calls; source attempts are per retained-core call, not hardware instructions

| Case | Publications | Native calls | Lowered operations | Code used bytes | Conditional calls | Whole-header calls | Compilation CPU | Source attempts/call |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 723 / 723 | 2,699,169 / 2,699,169 | 12,479,481 / 12,479,481 | 340,444 / 340,444 | 1,970,793 / 1,970,793 | 1,952,516 / 1,952,516 | 1.680 / 1.718 | 1,166,742 / 1,166,742 |
| minimal 100000 | 5 / 5 | 1,300,039 / 1,300,039 | 5,200,129 / 5,200,129 | 880 / 880 | 12 / 12 | 0 / 0 | 0.070 / 0.072 | 2,000,035 / 2,000,035 |
| memset 100000 | 54 / 54 | 3,900,351 / 3,900,351 | 9,101,412 / 9,101,412 | 5,488 / 5,488 | 3,900,151 / 3,900,151 | 1,300,084 / 1,300,084 | 0.198 / 0.194 | 1,200,349 / 1,200,349 |
| pinky 1 | 606 / 606 | 36,282,987 / 36,282,987 | 184,616,372 / 184,616,372 | 70,120 / 70,120 | 21,030,287 / 21,030,287 | 13,669,609 / 13,669,609 | 1.034 / 1.091 | 32,055,270 / 32,055,270 |
| sieve 10000000 | 750 / 750 | 271,619,743 / 271,619,743 | 1,250,782,976 / 1,250,782,976 | 345,768 / 345,768 | 199,590,176 / 199,590,176 | 195,021,015 / 195,021,015 | 1.821 / 1.732 | 123,322,753 / 123,322,753 |
| init 0 | 1,023 / 1,023 | 14,818,911 / 14,818,911 | 57,336,599 / 57,336,599 | 131,160 / 131,160 | 7,126,338 / 7,126,338 | 4,087,479 / 4,087,479 | 5.346 / 5.468 | 203,298,231 / 203,298,231 |
| tick 0 | 887 / 887 | 24,869,221 / 24,869,221 | 93,369,909 / 93,369,909 | 123,572 / 123,572 | 20,525,709 / 20,525,709 | 1,809,870 / 1,809,870 | 1.646 / 1.626 | 15,523,334 / 15,523,334 |
