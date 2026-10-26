# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Source-owned issue215 readiness corpus, separate from the historical JAM interface plan."""
from corpus_checks import CorpusGroup
from jam_fuzz_corpora import run_fuzzer_guest_reference

CORPORA = CorpusGroup()


@CORPORA.case
def jam_network_epochs_corpus(compiler, report, checks, libraries):
    """Execute independently calculated ordinary/skipped epochs and delayed255-to252/6 activation and nonempty guest siblings."""
    import jam_fuzzer_network_oracle as reference
    return run_fuzzer_guest_reference(compiler,report,checks,libraries,reference,
        ('jam_fuzzer_network','jam_network_ring_input'),profiles=[reference.parameters()]*17,forks=True,headers=True)
