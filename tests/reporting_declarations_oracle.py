# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Derive logical namespace declarations from independently authored GP histories; no posterior values cross this boundary."""
from state_layout_oracle import chapter_key, chapter_service, digest
from state_accounts_oracle import parse as metadata_parse
from state_service_values_oracle import key as value_key
from state_requests_oracle import key as request_key


def encode(rows):
    """Bound and encode explicit identities only; values remain owned by actual native candidate snapshots."""
    assert len(rows) <= 16
    assert [row[0] for row in rows] == sorted({row[0] for row in rows})
    result = len(rows).to_bytes(2,'little')
    for sid,storage,hashes in rows:
        assert 0 <= sid < 2**32 and len(storage)<=16 and len(hashes)<=64
        assert storage == sorted(set(storage)) and [row[0] for row in hashes] == sorted({row[0] for row in hashes})
        result += sid.to_bytes(4,'little')+len(storage).to_bytes(2,'little')
        for key in storage:
            assert len(key)<=1024
            result += len(key).to_bytes(2,'little')+key
        result += len(hashes).to_bytes(2,'little')
        for hashed,lengths in hashes:
            assert len(hashed)==32 and len(lengths)<=16 and all(0<=n<2**32-2 for n in lengths)
            assert lengths == sorted(set(lengths))
            result += hashed+len(lengths).to_bytes(2,'little')+b''.join(n.to_bytes(4,'little') for n in lengths)
    assert len(result)<=16384
    return result


def declaration(case, ids, *, blobs=(), request_pairs=((digest(b'I'),1),(digest(b'Q'),1)), raw_keys=(b'',b'\1\2',b'\5',b'\7')):
    """Apply GP forward namespace equations to our own derived maps, checking complete logical coverage before native execution."""
    states = [case['initial']]+[state for _,state,_ in case['steps']]
    entries = {pair for state in states for pair in state.items()}
    physical = {key for key,_ in entries}
    payloads = {value:digest(value) for _,value in entries}
    known = set(request_pairs)|{(digest(blob),len(blob)) for blob in blobs}
    rows = [];covered = {chapter_key(i) for i in range(1,17)}
    for sid in sorted(set(ids)):
        metadata = chapter_service(255,sid)
        if metadata not in physical:
            continue # Uncreated/refused candidates grant no namespace authority.
        covered.add(metadata)
        codes = {metadata_parse(state[metadata],105)[0] for state in states if metadata in state}
        preimages = {(payloads[value],len(value)) for key,value in entries if key==value_key('P',sid,payloads[value])}
        pairs = known|preimages
        lengths = {0,1,3}|{length for _,length in pairs}
        hashes = {hashed for hashed,_ in pairs}|codes
        storage = [key for key in sorted(set(raw_keys)) if value_key('S',sid,key) in physical]
        covered.update(value_key('S',sid,key) for key in storage)
        declared = []
        for hashed in sorted(hashes):
            requests = sorted(length for length in lengths if request_key(sid,hashed,length) in physical)
            has_value = value_key('P',sid,hashed) in physical
            if not requests and not has_value:
                continue # A candidate hash is not a declared physical identity without a GP-derived witness.
            if has_value:covered.add(value_key('P',sid,hashed))
            covered.update(request_key(sid,hashed,length) for length in requests)
            declared.append((hashed,requests))
        rows.append((sid,storage,declared))
    assert physical <= covered, 'independent logical namespace declarations must cover every authored map entry'
    return encode(rows),rows
