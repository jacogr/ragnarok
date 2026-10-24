# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Author current Thin Safrole component cases independently of production serialization/STF.

These complete six-chapter inputs plus an unrelated sentinel are component maps, not complete
sixteen-chapter JAM states. Expected entropy/time, markers and exact map roots use explicit Python
byte/hash equations. Thin credentials use the mathematical reference, not the maintained ABI.
The constant input ring commits six copies of G with the qualified v1 public SRS/domain512.
"""
import hashlib
from bandersnatch_thin_oracle import sign
from test_bandersnatch_thin_reference import G, encode
from test_codec import reference_encode as natural
from header_oracle import wire
from state_layout_oracle import chapter_key
from state_consensus_oracle import wire as consensus_wire
from state_trie_oracle import tree

RING = bytes.fromhex(
    'b941e7c73ae1ecc7dec523d98bccde31698f90bb0faf68683c058160b3fb5af498'
    'dc161d815b631931d3f208d7e46c61a949e7abad3ed35fd832d6ac6d01d85f2ae'
    '9633c7ff7a9790f8ab94b8c9446dfedfb3c3da2b49f61740e72b6bec10f9e92e'
    '630ae2b14e758ab0960e372172203f4c9a41777dadd529971d7ab9d23ab29fe0e9'
    'c85ec450505dde7f5ac038274cf')


def cases():
    """Supply two within-epoch cases and one epoch crossing with no tickets or offenders."""
    public = encode(G)
    records = b''.join(public+bytes([index+1])+bytes(303) for index in range(6))
    roster = natural(6)+records
    consensus = consensus_wire((records, RING, 1, public*12, b''))
    history = tuple(bytes([10+index])+bytes(31) for index in range(4))
    result = []
    # Every case retains the same declared original map shapes; only time/header/entropy outcomes vary.
    for previous, target in ((0, 1), (1, 7), (11, 12)):
        crossing = previous//12 != target//12
        source = {4: consensus, 6: b''.join(history), 7: roster, 8: roster, 9: roster,
                  11: previous.to_bytes(4, 'little')}
        parent_pairs = [(chapter_key(k), value) for k, value in source.items()]
        parent_pairs.append((chapter_key(1), bytes([91, 92, 93])))
        parent_root, _ = tree(parent_pairs)
        seal_input = b'jam_fallback_seal'+history[2 if crossing else 3]
        _, seal_output = sign(1, seal_input, b'')
        entropy_proof, entropy_output = sign(1, b'jam_entropy'+seal_output, b'')
        marker = None
        # The marker names parent eta[0]/eta[1] and posterior pending key pairs, never the fresh entropy.
        if crossing:
            marker = {'entropy': history[0], 'tickets_entropy': history[1],
                      'validators': [{'bandersnatch': public, 'ed25519': bytes([i+1])+bytes(31)}
                                     for i in range(6)]}
        header = {'parent': bytes(32), 'parent_state_root': parent_root,
                  'extrinsic_hash': bytes(32), 'slot': target, 'epoch_mark': marker,
                  'tickets_mark': None, 'author_index': 0, 'entropy_source': entropy_proof,
                  'offenders_mark': []}
        header['seal'], _ = sign(1, seal_input, wire('U', header))
        fresh = hashlib.blake2b(history[0]+entropy_output, digest_size=32).digest()
        posterior_history = (fresh, *history[:3]) if crossing else (fresh, *history[1:])
        expected = {4: consensus, 6: b''.join(posterior_history), 8: roster, 9: roster,
                    11: target.to_bytes(4, 'little')}
        result.append({'name': f'authored/{previous}-{target}', 'header': wire('H', header),
                       'source': source, 'expected': expected, 'entropy_output': entropy_output,
                       'parent_root': parent_root})
    return result
