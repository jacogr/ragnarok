"""Independent additional guarantee inspection/standalone expectations for the compiler trial."""
import random
from guarantees_oracle import (requests as extrinsic_requests, decode, encode, record, published,
                               wire, fields, token, ERRORS)
from report_oracle import decode as report_decode
from assurances_oracle import config_error
from test_codec import reference_decode


# Parse one standalone record directly, without adding a fictitious count or changing budget precedence.
def standalone(data, cores, validators, budget):
    error = config_error(cores, validators)
    if error:
        # No input is meaningful under an invalid chain configuration.
        return error
    report = report_decode(data, cores)
    if report in ERRORS:
        # The complete child report is checked before the wrapper's byte budget.
        return report
    parts = report.split()
    cursor, core = int(parts[-1]), int(parts[2])
    report_bytes = data[:cursor]
    if cursor > budget:
        # The consumed report alone can exhaust the frame budget.
        return 'limitexceeded'
    if len(data)-cursor < 4:
        # The slot remains fixed E4, independent of its numeric value.
        return 'truncated'
    slot = int.from_bytes(data[cursor:cursor+4], 'little')
    cursor += 4
    count = reference_decode(data[cursor:])
    if count in ('truncated', 'noncanonical'):
        # A missing/overlong credential count has no active credential alternative.
        return count
    size, progress = map(int, count.split())
    cursor += progress
    if cursor > budget:
        # Count bytes consume budget before its semantic cardinality is checked.
        return 'limitexceeded'
    if size not in (2, 3):
        # Exactly two or three credentials are allowed.
        return 'invalidcredential'
    if size > (len(data)-cursor)//66:
        # Prove all E2-index/signature pairs before reading them.
        return 'truncated'
    if cursor+66*size > budget:
        # The final credential must fit the complete retained prefix budget.
        return 'limitexceeded'
    credentials, previous = [], -1
    for _ in range(size):
        # Interpret every identity and opaque signature independently of native layout.
        index = int.from_bytes(data[cursor:cursor+2], 'little')
        if index >= validators:
            # E2 width alone does not prove membership in the configured population.
            return 'invalidvalidator'
        if index <= previous:
            # Duplicate and descending credentials are equally noncanonical.
            return 'noncanonical'
        credentials.append((index, data[cursor+2:cursor+66]))
        previous = index
        cursor += 66
    return core, cursor, dict(report=report_bytes, slot=slot, credentials=credentials)


# Keep all existing extrinsic cases intact and supplement every decode with direct inspection.
def requests():
    lines, expected = extrinsic_requests()
    counts = dict(extrinsic=len(lines), inspection=0, standalone=0)
    for line in list(lines):
        # Inspection validates the same exact input without creating retained report owners.
        parts = line.split()
        if parts[0] == 'D':
            result = decode(bytes.fromhex(parts[4]) if parts[4] != '-' else b'',
                            int(parts[1]), int(parts[2]), int(parts[3]))
            fields_out = result.split()
            lines.append(' '.join(['I', *parts[1:]]))
            expected.append(' '.join(fields_out[:2]) if len(fields_out) > 1 else result)
            counts['inspection'] += 1

    # Every standalone frame reaches both capture and allocation-free inspection with independent expectations.
    def add(data, cores=341, validators=1023, budget=4194304):
        result = standalone(data, cores, validators, budget)
        suffix = f'{cores} {validators} {budget} {token(data)}'
        lines.extend(['S '+suffix, 'J '+suffix])
        if isinstance(result, str):
            # Failed framing exposes neither a core nor a consumed prefix.
            expected.extend([result, result])
        else:
            # Observe all wrapper fields and child bytes as well as exact standalone extent.
            core, consumed, value = result
            expected.extend([str(consumed)+' '+fields([value])[2:], f'{core} {consumed}'])
        counts['standalone'] += 2

    examples = [published('tiny')[0], published('full')[0], record(0), record(340, 3)]
    for value in examples:
        # Serialize source fields independently and remove only the known one-record outer prefix.
        data = wire([value])[1:]
        add(data)
        add(data+b'\xaa\xbb', budget=len(data))
        for cut in range(len(data)):
            # Every cut includes the report, slot, credential count and final signature boundaries.
            add(data[:cut])
        for budget in (0, len(data)-1, len(data), 2**64-1):
            # Explicit frame ceilings apply only to consumed bytes, including at the uint64 maximum.
            add(data, budget=budget)
        for budget in (0, len(data)-1, len(data), 2**64-1):
            # Source measurement and fresh encoding share preflight, without an external output capacity.
            for mode in ('M', 'V'):
                lines.append(f'{mode} 341 1023 {budget} 0 '+fields([value]))
                encoded = encode([value], 341, 1023, budget+1, 4194304)
                if encoded in ERRORS or encoded in ('invalidcredential', 'invalidvalidator', 'invalidconfig', 'invalidreport'):
                    # The extra mathematical budget byte accounts only for the removed outer prefix.
                    expected.append(encoded)
                else:
                    # A single-record extrinsic starts with exactly one byte; the standalone payload follows.
                    expected.append(str(len(bytes.fromhex(encoded))-1) if mode == 'M' else encoded[2:])
                counts['standalone'] += 1
    for size in (0, 1, 4):
        # Malformed source cardinality is rejected by both scan and standalone source preflight.
        value = record(0)
        value['credentials'] = [(i, bytes(64)) for i in range(size)]
        add(wire([value])[1:])
        for mode in ('M', 'V'):
            lines.append(f'{mode} 341 1023 4194304 0 '+fields([value]))
            expected.append('invalidcredential')
            counts['standalone'] += 1
    for cores, validators in ((1, 6), (342, 6), (2, 7), (2**64-1, 6), (2, 2**64-1)):
        # Invalid unsigned configuration must fail before reading the absent report.
        add(b'', cores, validators)
    rng = random.Random(0x5354414e44414c4f)
    base = wire([record(0, 3)])[1:]
    for i in range(1500):
        # Deterministic structure-preserving mutations reach late fields as well as child framing.
        data = bytearray(base)
        for _ in range(rng.randrange(1, 5)):
            data[rng.randrange(len(data))] = rng.randrange(256)
        if i % 3 == 0:
            # Truncation combines extent and semantic errors in one independent corpus.
            data = data[:rng.randrange(len(data)+1)]
        add(bytes(data))
    for _ in range(500):
        # Random standalone bytes avoid reliance on a valid initial frame.
        add(rng.randbytes(rng.randrange(2000)))
    return lines, expected, counts
