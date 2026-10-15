# Shared setup and measurement limitations

This file is a later explanatory note, not a reconstructed execution log. During shared OpenSSL
fixture preparation, the first provider self-check used `public_key` for a pinned RFC 8032 JSON
field named `public`. Python raised `KeyError: public_key`; the harness was corrected to use the
actual fixture key. The original shell diagnostic appeared in this task but was not retained as a
standalone command log. Subsequent RFC known-answer and 42 composition checks per candidate passed.
This is one shared test-infrastructure error, not three native implementation defects.

The independent report oracle and composed measurement adapters were developed within the same
interleaved session as the native candidates. Shared work therefore falls inside the candidate
journals' raw elapsed intervals. Those timestamps are real command boundaries, but do not establish
comparable implementation-development times. The architecture/specification analysis also preceded
registration. Report comparative time-to-passing-tests as N/A and retain raw journal intervals only
as operational evidence. Candidate order was Odin, Mojo, Nim for initial report implementation;
benchmark/metadata work then overlapped within the same agent's context. Later candidates could see
earlier code. The exact serving-model version and reasoning configuration are unavailable.

Direct new candidate compiler attempts were journaled. Existing baseline scripts also compile their
own old targets; their detailed output is preserved as baseline/recheck evidence, not relabelled as
new implementation repair attempts. Intended type-rejection and compiler-reduction probes are
marked diagnostic. Three baseline rechecks run the same monolithic shared contract; zero confirmed
regressions over one registered check is not a statistical estimate of long-term defect rates.

The maintainer's LTO-only instruction preceded registration and is part of the initial contract,
not an additional counted intervention. No native behavior or tests were weakened for the metrics.

After native-task completion, the new CI diagnostic wrapper initially recognized different wording
than Mojo's actual `cannot implicitly convert` error. The native probe correctly rejected the
wrong hash domain. The wrapper was corrected to require that wording and both source/destination
domain names. This was a second shared diagnostic-infrastructure setup mismatch, outside the
completed native implementation cohort, not a native compiler repair or runtime defect.
