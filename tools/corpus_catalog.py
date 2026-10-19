# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compose feature-owned corpus tasks in dependency order, without repeating their result names.

Exposes CORPUS_NAMES and run_corpora for scheduling and expected report coverage. Shared driver
builds remain ordered before consumers; registration never executes an oracle or native process.
"""
from corpus_codec import CORPORA as CODECS
from corpus_state import CORPORA as STATE
from corpus_services import CORPORA as SERVICES
from corpus_crypto import BANDERSNATCH, CRYPTO
from corpus_network import CORPORA as NETWORK

GROUPS = (CODECS, STATE, SERVICES, BANDERSNATCH, NETWORK, CRYPTO)
CORPUS_NAMES = tuple(sorted(name for group in GROUPS for name in group.tasks))
if not CORPUS_NAMES or len(CORPUS_NAMES) != len(set(CORPUS_NAMES)):
    raise ValueError('Empty or duplicate corpus plan')


# Groups retain the historical shared-build dependency order and their original fixture inputs.
def run_corpora(compiler, report, checks, libraries, quic_fixtures, integration_wires):
    for group in GROUPS:
        # Only the network group consumes the generated certificates and integration input wires.
        extra = (quic_fixtures, integration_wires) if group is NETWORK else ()
        group.run(compiler, report, checks, libraries, *extra)
