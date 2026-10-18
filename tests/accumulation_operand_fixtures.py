# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP accone i^U report-to-operand expectations, preserving full upstream report inputs.

Exposes grouped for mathematical service filtering and prepare for six published queue scenarios
at three prefixes plus seeded authored reports. Expected C.2 bytes use the existing independent oracle.
"""
import hashlib
import json
import random
from accumulation_queue_fixtures import priority, report, row
from state_workqueues_oracle import blob
from report_oracle import encode
from c2_oracle import wire


# Numeric service enumeration changes only group order; report/digest order inside each group is preserved.
def grouped(selected, prefix):
    groups = {}
    for report in selected[:prefix]:
        value = report['layout']
        for service, code, payload_hash, gas, tag, payload, load in value['digests']:
            # Code hashes and refinement metrics are deliberately not members of an accumulation operand.
            header = value['header']
            operand = (header[:32], header[70:102], value['authorizer'], payload_hash,
                       gas, tag, payload, value['auth'])
            groups.setdefault(service, []).append(wire('O', operand))
    return [(service, groups[service]) for service in sorted(groups)]


# Transport unchanged queue inputs and complete expected operand bytes, with an explicit report-prefix count.
def case_row(name, cores, available, ready, history, slot, prefix):
    queue_fields = row(name, cores, available, ready, history, slot).split()[:7]
    selected, _, _ = priority(available, ready, history, slot)
    groups = grouped(selected, prefix)
    expected = ';'.join(str(s)+':'+','.join(x.hex() for x in operands) for s, operands in groups) or '-'
    return ' '.join([*queue_fields, str(prefix), expected])


# Published expectations cover the queue boundary; authored records cover all work tags and blob/gas boundaries.
def prepare(folder):
    lines = []
    template = None
    sources = []
    for chain, cores in (('tiny', 2), ('full', 341)):
        for name in ('accumulate_ready_queued_reports-1', 'enqueue_and_unlock_chain-1',
                     'enqueue_and_unlock_chain_wraps-1'):
            path = f'stf/accumulate/{chain}/{name}.json'
            case = blob(path)
            state = case['pre_state']
            ready = [[(report(x['report']), {bytes.fromhex(d[2:]) for d in x['dependencies']})
                      for x in bucket] for bucket in state['ready_queue']]
            available = [report(x) for x in case['input']['reports']]
            history = [{bytes.fromhex(x[2:]) for x in bucket} for bucket in state['accumulated']]
            selected, _, _ = priority(available, ready, history, case['input']['slot'])
            for prefix in (0, len(selected)//2, len(selected)):
                lines.append(case_row(path, cores, available, ready, history, case['input']['slot'], prefix))
            sources.append(path)
            if template is None:
                template = next(r['layout'] for bucket in ready for r, _ in bucket)
    rng = random.Random(0x4F504552414E44)
    for case in range(128):
        available = []
        for index in range(rng.randrange(1, 9)):
            header = bytearray(template['header'])
            header[:32] = bytes([index+1])+bytes(31)
            header[70:102] = bytes([index+40])*32
            services = sorted(rng.sample([0, 1, 42, 1729, 2**32-1], rng.randrange(1, 6)))
            digests = []
            for position, service in enumerate(services):
                tag = (case+index+position) % 7
                payload = bytes([index+3])*rng.choice((0, 1, 127, 128)) if tag == 0 else b''
                gas = rng.choice((0, 127, 128, 16383, 16384, 2**64-1))
                digests.append((service, bytes([77])*32, bytes([position+20])*32,
                                gas, tag, payload, [2**64-1, 0, 0, 0, 0]))
            layout = dict(template, header=bytes(header), core=index % 2, prerequisites=b'', lookup=b'',
                          authorizer=bytes([index+60])*32,
                          auth=bytes([case])*rng.choice((0, 1, 127, 128)), digests=digests)
            available.append(dict(key=bytes(header[:32]), wire=encode(layout), layout=layout,
                                  prerequisites=set(), lookup=set()))
        prefix = rng.randrange(len(available)+1)
        lines.append(case_row(f'authored-{case}', 2, available, [[] for _ in range(12)],
                              [set() for _ in range(12)], case, prefix))
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'accumulation-operands.txt'
    path.write_text('\n'.join(lines)+'\n')
    evidence = dict(published_projections=18, authored=128, sources=sources,
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'accumulation-operands.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
