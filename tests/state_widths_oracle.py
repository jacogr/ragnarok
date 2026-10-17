"""Diagnostic width alternatives over unchanged pinned STF binaries and serialized state values."""
import hashlib
import json
import subprocess
from test_support import ROOT
from test_codec import reference_encode as natural, reference_decode
from report_oracle import encode as report_wire, from_json
from state_layout_oracle import chapter_key, chapter_service

TRACE_PATHS = tuple(f'traces/fuzzy/{i:08}.json' for i in (25, 50, 100, 150, 200))+(
    'traces/fuzzy_light/00000200.json', 'traces/storage/00000100.json',
    'traces/preimages/00000100.json')


# Verify exact pinned Git bytes before parsing or using them to anchor any candidate span.
def blob(path):
    pin = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    data = subprocess.check_output(['git', '-C', str(ROOT/pin['path']), 'show', pin['commit']+':'+path])
    assert hashlib.sha256(data).hexdigest() == pin['git_blobs'][path], path
    return data


# Dictionary framing is held constant while service IDs and gas vary independently in the four candidates.
def privilege_wire(source, key_width, gas_width):
    roles = [source['bless'], *source['assign'], source['designate'], source['register']]
    pairs = source['always_acc']
    return b''.join(x.to_bytes(4, 'little') for x in roles)+natural(len(pairs))+b''.join(
        (x['id'].to_bytes(key_width, 'little') if key_width else natural(x['id']))+
        (x['gas'].to_bytes(gas_width, 'little') if gas_width else natural(x['gas'])) for x in pairs)


# Derive a binary offset by matching the entire preceding schema prefix, never by searching for pair bytes.
def privilege_binaries():
    evidence = []
    # Distinct profiles/cases include zero and nonzero input report counts ahead of the pre-state.
    for chain, slots in (('tiny', 12), ('full', 600)):
        for case in (1, 2):
            path = f'stf/accumulate/{chain}/always_accumulate-{case}'
            document = json.loads(blob(path+'.json'))
            raw = blob(path+'.bin')
            source = document['pre_state']
            assert len(source['ready_queue']) == slots and not any(source['ready_queue'])
            assert len(source['accumulated']) == slots and not any(source['accumulated'])
            prefix = document['input']['slot'].to_bytes(4, 'little')+natural(len(document['input']['reports']))
            prefix += b''.join(report_wire(from_json(report)) for report in document['input']['reports'])
            prefix += source['slot'].to_bytes(4, 'little')+bytes.fromhex(source['entropy'][2:])+bytes(2*slots)
            assert raw.startswith(prefix), (path, 'preceding schema prefix differs')
            candidates = []
            # Compare four candidates at exactly the verified offset, preserving all published source values.
            for key_width in (0, 4):
                for gas_width in (0, 8):
                    candidate = privilege_wire(source['privileges'], key_width, gas_width)
                    match = raw[len(prefix):len(prefix)+len(candidate)] == candidate
                    candidates.append(dict(key_width=key_width, gas_width=gas_width, bytes=len(candidate), matches=match))
            matches = [x for x in candidates if x['matches']]
            assert [(x['key_width'], x['gas_width']) for x in matches] == [(4, 8)], (path, candidates)
            size = matches[0]['bytes']
            value = raw[len(prefix):len(prefix)+size]
            evidence.append((value, dict(path=path, phase='pre_state', offset=len(prefix), bytes=size,
                binary_sha256=hashlib.sha256(raw).hexdigest(), json_sha256=hashlib.sha256(blob(path+'.json')).hexdigest(),
                value_sha256=hashlib.sha256(value).hexdigest(), pairs=source['privileges']['always_acc'],
                candidates=candidates, scope='STF Privileges field, not a raw T(12) trie entry')))
    return evidence


# Diagnostic failures carry no inferred fields: failed alternatives are not producer-intended values.
class WidthFailure(ValueError):
    pass


# Tiny bounded cursor supports canonical naturals or a deliberately specified fixed-width alternative.
class Cursor:
    # Own a test-only reference to immutable raw bytes and a bounded parsing position.
    def __init__(self, data):
        self.data = data
        self.offset = 0

    # Fixed reads prove presence before taking an exact span, including empty spans.
    def fixed(self, width):
        if width > len(self.data)-self.offset:
            raise WidthFailure('truncated')
        raw = self.data[self.offset:self.offset+width]
        self.offset += width
        return raw

    # A zero width selects canonical natural framing; nonzero widths select literal E4/E8 alternatives.
    def integer(self, width=0):
        if width:
            return int.from_bytes(self.fixed(width), 'little')
        decoded = reference_decode(self.data[self.offset:])
        if decoded in ('truncated', 'noncanonical'):
            raise WidthFailure(decoded)
        value, size = map(int, decoded.split())
        self.offset += size
        return value


# Re-emit every diagnosed field independently; complete byte identity is necessary for a candidate match.
def statistics_wire(source, key_width, gas_width):
    epochs, cores, services = source
    # Only the selected bounded domains vary; general count/measure fields remain canonical naturals.
    def integer(value, width):
        return value.to_bytes(width, 'little') if width else natural(value)
    result = b''.join(natural(len(epoch)//24)+epoch for epoch in epochs)
    result += b''.join(b''.join(natural(x) for x in row[:7])+integer(row[7], gas_width) for row in cores)
    result += natural(len(services))
    # Two service gas positions are kept separate from the nine ordinary measures.
    for key, fields in services:
        result += integer(key, key_width)
        result += b''.join(integer(value, gas_width if i in (3, 10) else 0) for i, value in enumerate(fields))
    return result


# Parse a diagnostic tiny-profile candidate completely, enforcing canonical values, key domains and ordering.
def statistics_candidate(data, key_width, gas_width):
    cursor = Cursor(data)
    try:
        epochs = []
        # Both selected trace epoch populations are exactly six, preserving their E4 counters.
        for _ in range(2):
            count = cursor.integer()
            if count != 6:
                raise WidthFailure('invalidcount')
            epochs.append(cursor.fixed(count*24))
        cores = []
        # Exactly two tiny cores have seven ordinary measures followed by the candidate gas representation.
        for _ in range(2):
            cores.append([cursor.integer() for _ in range(7)]+[cursor.integer(gas_width)])
        count = cursor.integer()
        if count > (len(data)-cursor.offset)//12:
            raise WidthFailure('truncated')
        services = []
        # Keys must remain uint32 and strictly increasing; no candidate sorts or repairs the original wire.
        for _ in range(count):
            key = cursor.integer(key_width)
            if key > 2**32-1:
                raise WidthFailure('invalidservice')
            if services and key <= services[-1][0]:
                raise WidthFailure('noncanonical_order')
            fields = [cursor.integer(gas_width if i in (3, 10) else 0) for i in range(11)]
            services.append((key, fields))
        if cursor.offset != len(data):
            raise WidthFailure('trailingbytes')
        source = (epochs, cores, services)
        assert statistics_wire(source, key_width, gas_width) == data
        return dict(matches=True, services=[key for key, _ in services],
            core_gas=[row[7] for row in cores], service_gas=[(fields[3], fields[10]) for _, fields in services])
    except WidthFailure as failure:
        return dict(matches=False, error=str(failure)) # No partial logical values are reported for rejected schemas.


# Raw T(12/13) observations from the bounded eight-snapshot search preserve the supplied values exactly.
def trace_values():
    result = []
    # Search scope is explicit rather than implying exhaustive reference coverage from sampled snapshots.
    for path in TRACE_PATHS:
        raw = blob(path)
        document = json.loads(raw)
        for phase in ('pre_state', 'post_state'):
            pairs = [(bytes.fromhex(x['key'][2:]), bytes.fromhex(x['value'][2:])) for x in document[phase]['keyvals']]
            privilege = [value for key, value in pairs if key == chapter_key(12)]
            activity = [value for key, value in pairs if key == chapter_key(13)]
            assert len(privilege) == len(activity) == 1
            assert len(privilege[0]) == 21 and privilege[0][20:] == b'\0', 'update nonempty T12 audit'
            candidates = []
            # Service keys and all gas positions vary independently; exact matches must reconstruct all original bytes.
            for key_width in (0, 4):
                for gas_width in (0, 8):
                    candidates.append(dict(key_width=key_width, gas_width=gas_width,
                        **statistics_candidate(activity[0], key_width, gas_width)))
            selected = next(x for x in candidates if x['key_width'] == 4 and x['gas_width'] == 0)
            assert selected['matches'], (path, phase, candidates)
            # Wide diagnostic service IDs independently identify existing full metadata keys in the same state.
            keys = {key for key, _ in pairs}
            metadata_keys = [chapter_service(255, service) for service in selected['services']]
            assert all(key in keys for key in metadata_keys), (path, phase, 'diagnostic service has no metadata')
            result.append((privilege[0], activity[0], dict(path=path, phase=phase,
                blob_sha256=hashlib.sha256(raw).hexdigest(), privilege_dictionary_items=0,
                privilege_sha256=hashlib.sha256(privilege[0]).hexdigest(),
                activity_sha256=hashlib.sha256(activity[0]).hexdigest(), candidates=candidates,
                matching_metadata_keys=[key.hex() for key in metadata_keys])))
    return result


# Replay the frozen width evidence through exact capture without selecting new encoding rules.
def requests():
    from state_composition_oracle import chapters, capture, PROFILE, POLICY
    from state_layout_oracle import token
    binaries, traces = privilege_binaries(), trace_values()
    lines = ['B '+' '.join(map(str, PROFILE))+' '+' '.join(token(v) for v in chapters())]
    expected = ['selftest']
    records = []
    # Each exact-capture request records its identity and current decoder's complete-entry verdict.
    def add(chapter, raw, profile, identity):
        wanted = capture(chapter, raw, profile)
        lines.append('C '+' '.join(map(str, (*profile, *POLICY, chapter)))+' '+token(raw))
        expected.append(wanted)
        records.append(dict(**identity, chapter=chapter, current_expected=wanted))
    # Nonempty binaries are explicitly STF fields, not original Merkle-trie T12 values.
    for raw, evidence in binaries:
        profile = (2, 6, 6, 12) if '/tiny/' in evidence['path'] else (341, 1023, 1023, 600)
        add(12, raw, profile, dict(path=evidence['path']+'.bin', phase='pre_state'))
    # Both chapters are observed at exact original value extents, without replacing any wire field.
    for privilege, activity, evidence in traces:
        for chapter, raw in ((12, privilege), (13, activity)):
            add(chapter, raw, (2, 6, 6, 12), dict(path=evidence['path'], phase=evidence['phase']))
    return lines, expected, records, binaries, traces
