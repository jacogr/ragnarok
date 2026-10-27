#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Add one declared four-pair cold-init replication and complete-process memory observations.

All original timings remain included. Exact qualified images and source seals are reused;
resource-probe clocks are discarded. This is not an adaptive search for favorable repetitions.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
from types import SimpleNamespace
from compare import Comparison, ROOT, SOURCE


def main():
    """Only a completed unchanged cohort may receive this single fixed replication."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name')
    parser.add_argument('--deadline', required=True)
    args = parser.parse_args()
    if not args.name or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in args.name):
        parser.error('Expected a simple experiment name')
    folder = ROOT/'build/pvm-interpreter-experiment/comparisons'/args.name
    data = json.loads((folder/'results.json').read_text())
    if data['status'] != 'passed' or data.get('confirmation_plan'):
        parser.error('Expected a completed cohort without previous replication')
    old = ROOT/'build/pvm-port-lab/large-app-qualification'
    subject = Comparison(SimpleNamespace(name=args.name, deadline=args.deadline, baseline=data['baseline'],
        doom_fixtures=old/'prepared', rom=ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad'))
    subject.report = data
    subject.verify()
    shutil.copy2(folder/'results.json', folder/'results-before-confirmation.json')
    subject.report.update(status='confirming', confirmation_plan=dict(cold_init_additional_pairs=4,
        original_pairs_retained=True, resource_probe_clocks='discarded'))
    subject.seal([SOURCE/'confirm.py'])
    try:
        for order in range(2, 6):
            roles = ['baseline', 'candidate']
            for role in roles if order % 2 == 0 else reversed(roles):
                subject.record(subject.doom(role, 'init', order, cold=True))
            print('PASS additional cold-init pair '+str(order), flush=True)
        resources = []
        for phase in ('init', 'tick'):
            for order in range(2):
                roles = ['baseline', 'candidate']
                for role in roles if order % 2 == 0 else reversed(roles):
                    # Peak RSS includes the entire checked process; it is never labeled engine-only memory.
                    env = dict(os.environ, RAGNAROK_PVM_DOOM_INPUT=str(old/'prepared'),
                        RAGNAROK_PVM_DOOM_ROM=str(subject.args.rom), RAGNAROK_PVM_DOOM_PHASE=phase,
                        RAGNAROK_PVM_DOOM_TIMING='0', RAGNAROK_PVM_LOCAL_ONECALL='1')
                    row, text = subject.command(['/usr/bin/time', '-l', folder/(role+'-doom')],
                        f'resource-{phase}-{order}-{role}', env)
                    matched = re.search(r'(\d+)\s+maximum resident set size', text)
                    if row['exit_code'] != 0 or 'DOOM_OK,' not in text or matched is None:
                        raise RuntimeError('Resource observation failed: '+row['log'])
                    resources.append(dict(phase=phase, order=order, role=role,
                        peak_rss_bytes=int(matched.group(1)), log=row['log']))
            print('PASS full-process RSS observations '+phase, flush=True)
        subject.verify()
        subject.report.update(status='passed', resource_observations=resources, all_inputs_stable=True)
    except (OSError, ValueError, RuntimeError) as error:
        subject.report.update(status='failed', error=str(error)); raise
    finally:
        subject.save()


if __name__ == '__main__':
    main()
