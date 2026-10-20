# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete report bytes from literal sources, pinned-table gas and Lagrange availability roots."""
from functools import lru_cache
from pvm_bundle_reference import digest, fixed, natural, immediate, preimage, fetched, witnesses as bundle_witnesses
from pvm_bundle_erasure_reference import bundle_bytes, encode
from pvm_availability_reference import witnesses as availability_witnesses, balanced
from pvm_gas_reference import simulate, tables


@lru_cache(maxsize=1)
def definitions():
    """Read the pinned GP gas tables through the existing independent simultaneous-transition model."""
    return tables()


def gas(program, host=0):
    """Charge the complete original gas block and the separately specified host work."""
    return simulate(program, definitions())[0]+host


def context_case():
    """Build literal nonzero context/prerequisites before package hashing and erasure coding."""
    old = bundle_bytes()
    package = bytes.fromhex(bundle_witnesses()['ordinary']['package'])
    key = lambda value: bytes([value])+bytes(31)
    context = key(1)+fixed(10, 4)+key(2)+key(3)+key(4)+fixed(20, 4)+key(5)
    context_wire = context+b'\2'+key(6)+key(7)
    # The original package fixed host/hash prefix is 36 bytes; its context has 168 fixed bytes and E(0).
    changed = package[:36]+context_wire+package[205:]
    data = changed+old[len(package):]
    leaves = [digest(chunk)+bytes(32) for chunk in encode(data, 6)]
    availability = digest(changed)+fixed(len(data), 4)+balanced(leaves)+fixed(6, 2)+bytes(32)+fixed(0, 2)
    return availability, context_wire, bytes([11, 12, 13])


def work_digest(program, index, exports, kind=0, output=b'', imports=0, extrinsics=0, extrinsic_bytes=0, host=0, missing=False):
    """Encode every C field and all five load metrics independently from original literal declarations."""
    payload = bytes([81, 42+index])
    result = bytes([kind])+(natural(len(output))+output if kind == 0 else b'')
    used = 0 if missing else gas(program, host)
    return (fixed(42+index, 4)+digest(preimage(program))+digest(payload)+fixed(100, 8)+result
            +b''.join(natural(value) for value in [used, imports, extrinsics, extrinsic_bytes, exports]))


@lru_cache(maxsize=1)
def witnesses():
    """Return full canonical bytes and report hashes without reading production output or runtime metadata."""
    halt = bytes([50, 0])
    good = [immediate(7, 65536), immediate(8, 3), bytes([10, 8]), immediate(8, 0), halt]
    context = bytes(132)+fixed(20, 4)+bytes(32)+b'\0'
    values = availability_witnesses()
    result = {}
    for name, kind in [('Empty', 0), ('Single', 1), ('Mixed', 3), ('Paged', 65), ('Context', 4)]:
        auth = [halt]
        # Halt returns the initialized argument pointer/length: Is-Authorized receives exactly E2(core).
        trace, lookup = fixed(0x1234, 2), b'\0'
        ctx = context
        if kind == 4:
            availability, ctx, trace = context_case()
            auth = [immediate(7, 65536), immediate(8, 3), halt]
            # Both references retain their actual input counts; selector 4 charges 85+ceil(3*96/1024), selector 6 charges 171.
            digests = [work_digest(fetched(4), 0, 0, output=b'abc', imports=1, extrinsics=1, extrinsic_bytes=3, host=86),
                       work_digest(fetched(6), 1, 0, output=bytes([2, 0, 0]), imports=1, extrinsics=1, extrinsic_bytes=3, host=171)]
            # The tagged second import's dictionary root is the independent three-segment tree root from the literal manifest.
            leaves = [digest(b'leaf'+bytes([i])+bytes(4103)) for i in [1, 2, 3]]
            tree = digest(b'node'+digest(b'node'+leaves[0]+leaves[1])+digest(b'node'+leaves[2]+bytes(32)))
            lookup = b'\1'+bytes([1])+bytes(31)+tree
        else:
            availability = values[name]['wire']
            if kind == 0:
                digests = [work_digest([immediate(8, 0), halt], 0, 0)]
            elif kind == 1:
                digests = [work_digest(good, 0, 1, host=3521)]
            elif kind == 3:
                digests = [work_digest(good, 0, 1, host=3521), work_digest([halt], 1, 1, kind=3, missing=True),
                           work_digest(good[:3]+[bytes([0])], 2, 1, kind=3, host=3521)]
            else:
                digests = [work_digest([halt], 0, 65, kind=3, missing=True)]
        authorizer = digest(digest(preimage(auth))+bytes([81, 82]))
        wire = (availability+ctx+natural(0x1234)+authorizer+natural(gas(auth))+natural(len(trace))+trace
                +lookup+natural(len(digests))+b''.join(digests))
        result[name] = dict(wire=wire, hash=digest(wire))
    return result
