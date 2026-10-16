"""Test-only local account/solicit witnesses for pinned GP 0.8.0 namespace ambiguity; no PVM runtime."""
from dataclasses import dataclass, replace
import hashlib
from state_requests_oracle import key as request_key
from state_service_values_oracle import key as value_key
from state_composition_oracle import chapters, service_token, composed
from state_layout_oracle import MAX

U32 = 2**32-1
U64 = 2**64-1
BASE, ITEM, BYTE, SOLICIT_GAS = 100, 10, 1, 2193


# Small test-only account maps model just cited local predicates; functional code/execution is outside scope.
@dataclass
class Account:
    storage: dict
    preimages: dict
    requests: dict
    balance: int = 0
    gratis: int = 0


# Advertised lengths are charged as integers, without allocating the advertised blob.
def footprint(account):
    items = 2*len(account.requests)+len(account.storage)
    octets = sum(81+length for _, length in account.requests)
    octets += sum(34+len(key)+len(value) for key, value in account.storage.items())
    return items, octets


# The pinned constants and equations use a uint64 balance domain; zero gratis is enough for these witnesses.
def threshold(account):
    items, octets = footprint(account)
    return max(0, BASE+ITEM*items+BYTE*octets-account.gratis)


# These are explicit account-domain, preimage and deposit checks, not an exhaustive valid-state predicate.
def local_checks(account):
    items, octets = footprint(account)
    return dict(balance_domain=0 <= account.balance <= U64, gratis_domain=0 <= account.gratis <= U64,
        item_domain=0 <= items <= U32, octet_domain=0 <= octets <= U64,
        funded=account.balance >= threshold(account),
        request_domains=all(len(h) == 32 and 0 <= n <= U32 and len(slots) <= 3 and
            all(0 <= slot <= U32 for slot in slots) for (h, n), slots in account.requests.items()),
        preimage_constraints=all(hashlib.blake2b(value, digest_size=32).digest() == h and
            (h, len(value)) in account.requests for h, value in account.preimages.items()))


# Literal fresh-request Omega_S branches: length, readable hash, pair absence, and posterior deposit.
def fresh_solicit(account, identity, length, readable=True, gas=SOLICIT_GAS):
    if gas < SOLICIT_GAS:
        return 'OOG', account # The common accumulate-host wrapper checks gas before the function-specific branches.
    if not 0 <= length <= U32:
        return 'HUH', account # The domain check precedes memory failure in the cited return branches.
    if not readable:
        return 'PANIC', account # Only the 32-byte hash memory span is read, not length bytes.
    assert len(identity) == 32, 'readable hash fixture must supply exactly 32 bytes'
    if (identity, length) in account.requests:
        if len(account.requests[(identity, length)]) == 2:
            raise ValueError('restoration is outside the fresh-solicit model')
        return 'HUH', account # Existing empty/one/three-slot cases cannot enter the fresh-insertion branch.
    after = replace(account, requests={**account.requests, (identity, length): ()})
    if after.balance < threshold(after):
        return 'FULL', account # Failed deposits leave the original mapping unchanged.
    return 'OK', after


# Encode exact version-zero metadata with derived footprint; other fixed fields are zero in this structural fixture.
def metadata(account):
    items, octets = footprint(account)
    values = [account.balance, 0, 0, octets, account.gratis]
    return b'\0'+bytes(32)+b''.join(value.to_bytes(8, 'little') for value in values)+items.to_bytes(4, 'little')+bytes(12)


# Typed composition sources preserve original maps without inventing lookup identities from trie digest bytes.
def service(account, service_id):
    return (service_id, metadata(account), list(account.storage.items()), list(account.preimages.items()),
        [(h, n, slots) for (h, n), slots in account.requests.items()], [])


# Each marker has a tiny conflicting value, a funded predecessor, and a collision-free adjacent control length.
def witnesses():
    result = []
    # A wrong-length additional request is not excluded by the one-way preimage invariant or solicit pair lookup.
    for kind, marker in (('preimage', U32-1), ('storage', U32)):
        identity = hashlib.blake2b(b'p', digest_size=32).digest()
        if kind == 'preimage':
            before = Account({}, {identity: b'p'}, {(identity, 1): (0,)}) # Correct hash/content and actual-length history already exist.
            counterpart = value_key('P', 7, identity)
        else:
            before = Account({identity: b'v'}, {}, {}) # No huge blob or preimage is required for a storage-key overlap.
            counterpart = value_key('S', 7, identity)
        prospective = replace(before, requests={**before.requests, (identity, marker): ()})
        before = replace(before, balance=threshold(prospective))
        status, after = fresh_solicit(before, identity, marker)
        assert status == 'OK' and all(local_checks(before).values()) and all(local_checks(after).values())
        collision_key = request_key(7, identity, marker)
        assert collision_key == counterpart
        assert (b'p' if kind == 'preimage' else b'v') != b'\0' # The colliding raw values disagree with requested-history encoding.
        control_status, control = fresh_solicit(before, identity, U32-2)
        assert control_status == 'OK' and all(local_checks(control).values())
        assert request_key(7, identity, U32-2) != counterpart
        result.append(dict(kind=kind, marker=marker, identity=identity, before=before, after=after,
            control=control, key=collision_key, status=status))
    return result


# Before/control states have complete roots; posterior marker states must reject duplicate identities.
def requests():
    values = chapters()
    lines = ['B 2 6 6 2 '+' '.join(value.hex() for value in values)]
    expected = ['selftest']
    evidence = []
    # All predecessor and control roots use tight literal metadata and tiny payloads despite large advertised lengths.
    for witness in witnesses():
        outcomes = {}
        # Compare the predecessor, adjacent-length control and overlapping posterior through identical codecs.
        for phase in ('before', 'control', 'after'):
            source = service(witness[phase], 7)
            lines.append('S '+' '.join(map(str, (MAX, MAX, MAX, MAX, 32, 0)))+' - '+service_token(source))
            verdict = composed(values, [source], (MAX,)*4, 32)
            expected.append(verdict)
            outcomes[phase] = verdict.split()[0]
        assert outcomes['after'] == 'duplicatekey' and outcomes['before'] != 'duplicatekey' and outcomes['control'] != 'duplicatekey'
        items, octets = footprint(witness['after'])
        evidence.append(dict(kind=witness['kind'], length=witness['marker'], lookup_hash=witness['identity'].hex(),
            collision_key=witness['key'].hex(), local_result=witness['status'], assumed_solicit_gas=SOLICIT_GAS,
            readable_hash_bytes=32, advertised_blob_bytes_allocated=0,
            actual_storage_preimage_bytes=sum(len(k)+len(v) for k, v in witness['after'].storage.items())+
                sum(len(v) for v in witness['after'].preimages.values()),
            posterior_items=items, posterior_octets=octets, balance=witness['after'].balance,
            posterior_threshold=threshold(witness['after']), local_checks=local_checks(witness['after']),
            composition=outcomes, scope='fresh-solicit local rule witness; no PVM execution or genesis reachability claim'))
    return lines, expected, evidence
