# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent first-accseq oracle using exhaustive prefix sums and arbitrary-precision gas.

Exposes initial for mathematical prefix selection and prepare for unchanged pinned queue inputs
plus authored gas-boundary reports. Expected service inputs reuse the independent C.2 oracle.
"""
import hashlib
import json
import random
from accumulation_queue_fixtures import priority, report, row
from accumulation_operand_fixtures import grouped
from accumulation_input_fixtures import invocation
from state_workqueues_oracle import blob
from report_oracle import encode
from preview_vectors import ACCUMULATION_GAS_CASES, accumulation_cases, blob as preview_blob, pins as preview_pins
from test_codec import reference_encode as natural


# Enumerate every prefix independently of the native incremental subtraction algorithm.
def initial(costs, cores, report_gas, block_gas, allowances):
    free = sum(allowances.values())
    budget = max(block_gas, report_gas*cores+free)
    if budget >= 2**64:
        return None  # GP gas cannot represent this initial context.
    prefix = max(i for i in range(len(costs)+1) if sum(costs[:i])+free <= budget)
    return budget, free, prefix, sum(costs[:prefix]), bool(prefix or allowances)


def context(path, cores, case):
    """Project complete reports and queue chapters without reading service execution state."""
    state = case['pre_state']
    ready = [[(report(x['report']), {bytes.fromhex(d[2:]) for d in x['dependencies']})
              for x in bucket] for bucket in state['ready_queue']]
    available = [report(x) for x in case['input']['reports']]
    history = [{bytes.fromhex(x[2:]) for x in bucket} for bucket in state['accumulated']]
    return path, cores, available, ready, history, case['input']['slot']


def result_row(fields, selected, gas, allowances, expected):
    """Attach the independent gas verdict and exact C.2 inputs for the selected prefix."""
    allowance_text = ','.join(f'{s}:{g}' for s, g in sorted(allowances.items())) or '-'
    if expected is None:
        # An unrepresentable gas budget carries no prepared groups.
        result = 'overflow -'
    else:
        budget, free, prefix, reserved, dispatch = expected
        groups = invocation(dict(grouped(selected, prefix)), [], allowances)
        result = ','.join(map(str, (budget, free, prefix, reserved, int(dispatch))))+' '
        result += ';'.join(f'{s}:{gas}:'+(','.join(x.hex() for x in items) or '-')
                           for s, gas, _, items in groups) or '-'
    return ' '.join([*fields, *map(str, gas), allowance_text, result])


def preview_rows():
    """Replay selected Tiny/Full initial rounds from the paired source reports."""
    rows, sources = [], []
    for profile, cores, block in (('tiny', 2, 20_000_000), ('full', 341, 16_450_000_000)):
        for path in accumulation_cases(profile):
            raw = preview_blob(path+'.json')
            binary = preview_blob(path+'.bin')
            case = json.loads(raw)
            _, _, available, ready, history, slot = context(path, cores, case)
            prefix = slot.to_bytes(4, 'little') + natural(len(available))
            prefix += b''.join(item['wire'] for item in available)
            assert binary.startswith(prefix), path
            assert not case['pre_state']['privileges']['always_acc'], path
            selected, _, _ = priority(available, ready, history, slot)
            costs = [sum(d[3] for d in item['layout']['digests']) for item in selected]
            gas = (47_000_000, block)
            expected = initial(costs, cores, *gas, {})
            assert expected is not None, path
            if path.rsplit('/', 1)[1] in ACCUMULATION_GAS_CASES:
                # Full defers the second report. The client's 94M Tiny floor admits both.
                assert len(selected) == 2, path
                assert expected[2] == (1 if profile == 'full' else 2), path
            post = {bytes.fromhex(x[2:]) for bucket in case['post_state']['accumulated'] for x in bucket}
            assert post-set().union(*history) == {item['key'] for item in selected}, path
            fields = row('preview:'+path, cores, available, ready, history, slot).split()[:7]
            rows.append(result_row(fields, selected, gas, {}, expected))
            sources.append(dict(path=path, json_sha256=hashlib.sha256(raw).hexdigest(),
                                binary_sha256=hashlib.sha256(binary).hexdigest()))
    return rows, sources


# Keep original reports and queue chapters unchanged; only the explicit planning policy is authored.
def prepare(folder):
    contexts = []
    sources = []
    template = None
    # These pinned scenarios supply independent tiny/full queue priorities without simulating execution.
    for chain, cores in (('tiny', 2), ('full', 341)):
        # Preserve dependency-ready and wraparound scenarios as distinct original inputs.
        for name in ('accumulate_ready_queued_reports-1', 'enqueue_and_unlock_chain-1',
                     'enqueue_and_unlock_chain_wraps-1'):
            path = f'stf/accumulate/{chain}/{name}.json'
            case = blob(path)
            ctx = context(path, cores, case)
            contexts.append(ctx)
            sources.append(path)
            if template is None:
                # Capture one original payload layout only for the explicitly authored cases below.
                template = next(r['layout'] for bucket in ctx[3] for r, _ in bucket)
    rng = random.Random(0x524F554E44)
    # Authored reports cover all work results, zero costs and sums larger than the gas domain.
    for case in range(128):
        available = []
        # Distinct package identities retain deterministic priority, including genuinely empty queues.
        for index in range(rng.randrange(9)):
            header = bytes([index+1])+template['header'][1:]
            digests = []
            # Mix all work tags and full-width gas within individual indivisible reports.
            for position in range(rng.randrange(1, 5)):
                tag = (case+index+position) % 7
                digests.append((position, bytes([77])*32, bytes([position+20])*32,
                                rng.choice((0, 1, 10, 128, 2**64-1)), tag,
                                bytes([index])*3 if tag == 0 else b'', [0]*5))
            layout = dict(template, header=header, core=index % 2, prerequisites=b'', lookup=b'',
                          auth=bytes([case])*3, digests=digests)
            available.append(dict(key=header[:32], wire=encode(layout), layout=layout,
                                  prerequisites=set(), lookup=set()))
        contexts.append((f'authored-{case}', 2, available, [[] for _ in range(12)],
                         [set() for _ in range(12)], case))
    lines = []
    refused = 0
    # Derive original queue priority first; gas policies may select only a prefix of that sequence.
    for name, cores, available, ready, history, slot in contexts:
        selected, _, _ = priority(available, ready, history, slot)
        costs = [sum(d[3] for d in r['layout']['digests']) for r in selected]
        # Exact, below-budget, maximum and multiplication/allowance-overflow contexts are explicit policies.
        for variant in range(5):
            allowances = {0: 0, 99: variant} if variant % 2 else {}
            report_gas = (0, 10, 0, 0, 2**64-1)[variant]
            block_gas = (0, 0, min(sum(costs), 2**64-1),
                         min(max(0, sum(costs)-1), 2**64-1), 0)[variant]
            expected = initial(costs, cores, report_gas, block_gas, allowances)
            fields = row(name, cores, available, ready, history, slot).split()[:7]
            if expected is None:
                # No success metadata or partial groups accompany an unrepresentable budget.
                refused += 1
            lines.append(result_row(fields, selected, (report_gas, block_gas), allowances, expected))
    preview, preview_sources = preview_rows()
    lines.extend(preview)
    folder.mkdir(parents=True, exist_ok=True)
    path = folder/'accumulation-round.txt'
    path.write_text('\n'.join(lines)+'\n')
    evidence = dict(sources=sources, published_contexts=30, authored_contexts=640, overflow=refused,
                    preview_commit=preview_pins()['commit'], preview_sources=preview_sources,
                    fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'accumulation-round.json').write_text(json.dumps(evidence, indent=2)+'\n')
    return path, evidence
