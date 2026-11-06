# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Disposable same-runner DOOM comparison of the two qualified x86 read policies."""
import json
import math
from pathlib import Path
import statistics

from pvm_ci_performance import PerformanceRunner, command_record, digest
from pvm_jit_platform import RESIDENT_PAIR_REF, RESIDENT_PROOF
from pvm_performance_report import _execution, _policy

STACK, RESIDENT = 'stack', 'resident'
STACK_FLAGS = ['pvmX86Jit']
RESIDENT_FLAGS = [*STACK_FLAGS, RESIDENT_PROOF]
JIT_ORDER = (STACK, RESIDENT, RESIDENT, STACK, RESIDENT, STACK, STACK, RESIDENT)
SCHEDULE = (
    ('interpreted', STACK), ('interpreted', RESIDENT),
    *(('jit', policy) for policy in JIT_ORDER),
    ('interpreted', RESIDENT), ('interpreted', STACK),
)
CLOCKS = ('cpu_ns', 'wall_ns')
WINDOWS = ('cold', 'reused', 'total')
FROZEN_REFERENCE = '471a5b68f9dfa41e49b5d2fe80c394c1a8d68a3d'
FROZEN_ROM = '1d7d43be501e67d927e415e0b8f3e29c3bf33075e859721816f652a526cac771'
FROZEN_DOOM = {
    'doom/doom.polkavm': '6ba024eaba62a18732b40340f209523c3bc0bdca7e0cca4b121e4e1342a07f32',
    'doom/golden.tga': '537fc5826ae6346f809ebea62c49207096e4cd21b7dc0b39f739a851eca40a8f',
    'doom/prepared/init.events': '8c1f2b13b28beba5895c041b6b58f21d365ab6560b24552b8ff1711b49912756',
    'doom/prepared/init.expected': '036dcc71335e5682bbeee5631ffb882aa97a0c4e4fde6145d2efd56535898c45',
    'doom/prepared/init.input': 'cb3fbd6f7299193703e7ff335cf103d3a8df4032d4814f0d94b58b7ab6256ef7',
    'doom/prepared/tick.events': '845a32d2f454cc3659ef8714f40974a3f5297f734a59d15b7c88794d3304c0cc',
    'doom/prepared/tick.expected': 'c0885497b0a1f47c410c7e017bed369c76e1520947da9b9f372326b830eb2d52',
    'doom/prepared/tick.input': 'f5fa6a78d876a8c98ae57c3c4dd9aee8ecdf587f354566d3549d209f5df63c71',
}


def invocation_clocks(samples):
    """Keep the canonical cold, reused and complete thirteen-call windows separate."""
    return {clock: dict(cold=samples[0][clock],
                        reused=statistics.median(row[clock] for row in samples[3:13]),
                        total=sum(row[clock] for row in samples)) for clock in CLOCKS}


def compare_case(rows):
    """Derive pair ratios and a conservative observed movement envelope from raw samples."""
    if tuple((row['role'], row['staging']) for row in rows) != SCHEDULE:
        raise ValueError('Incomplete or misordered resident pair schedule')
    values = [invocation_clocks(row['parsed']['invocation']['samples']) for row in rows]
    result = []
    for clock in CLOCKS:
        for window in WINDOWS:
            times = [value[clock][window] for value in values]
            # Indexes include the interpreted S/R bracket at the beginning and R/S at the end.
            pairs = [(2, 3), (5, 4), (7, 6), (8, 9)]
            pair_ratios = [times[r]/times[s] for s, r in pairs]
            drift = {RESIDENT:times[4]/times[3], STACK:times[8]/times[7]}
            interpreted = [times[1]/times[0], times[10]/times[11]]
            logs = [math.log(ratio) for ratio in pair_ratios]
            by_order = {
                STACK: statistics.median((logs[0], logs[3])),
                RESIDENT: statistics.median((logs[1], logs[2])),
            }
            envelope = max(abs(math.log(ratio)) for ratio in (*drift.values(), *interpreted))
            verdict = 'inconclusive'
            if all(value < -envelope for value in by_order.values()):
                verdict = 'resident-faster'
            elif all(value > envelope for value in by_order.values()):
                verdict = 'resident-slower'
            result.append(dict(clock=clock, window=window, process_ns=times,
                resident_over_stack=pair_ratios, same_image_later_over_earlier=drift,
                interpreted_resident_over_stack=interpreted,
                median_ratio_by_first={policy:math.exp(value) for policy,value in by_order.items()},
                observed_envelope_factor=math.exp(envelope), verdict=verdict))
    return result


class PairedRunner(PerformanceRunner):
    """Reuse the canonical proof, frozen fixtures, application controls and full-call parser."""

    def __init__(self, folder, scope, expected_revision=None):
        super().__init__(folder, scope, expected_revision)
        self.report.update(schema='pvm-resident-pair-v1', images={})
        self.staging = None
        self.log_prefix = ''
        self.log_names = set()

    def checkpoint(self):
        temporary = self.folder/'resident-pair.json.tmp'
        temporary.write_text(json.dumps(self.report, indent=2)+'\n')
        temporary.replace(self.folder/'resident-pair.json')

    def command(self, arguments, name, env=None, timeout=900, expected_failure=False):
        name = self.log_prefix+name
        if name in self.log_names or (self.folder/(name+'.log')).exists():
            raise ValueError('Duplicate resident pair log: '+name)
        self.log_names.add(name)
        return super().command(arguments, name, env, timeout, expected_failure)

    def parse(self, output, case, role):
        parsed = super().parse(output, case, role)
        row = parsed[case['case_id']]
        _execution(row['invocation'], case['case_id'] if role == 'reference' else None)
        _policy(row, role)
        if role == 'reference':
            return parsed
        expected = dict(fragments=0, calls=0, operations=0, code_bytes=0, branches=0, headers=0)
        if role == 'jit':
            if case['case'] == 'init':
                expected.update(fragments=1, calls=12, operations=24, code_bytes=36)
            else:
                expected.update(fragments=1, calls=1536000, operations=33792000,
                                code_bytes=1259 if self.staging == RESIDENT else 1330)
        if row['native'] != expected:
            raise ValueError(f'Unexpected resident pair work for {case["case_id"]}/{role}/{self.staging}')
        return parsed

    def build_pair(self):
        qualified = self.defines
        commands = []
        for staging, defines in ((STACK, STACK_FLAGS), (RESIDENT, RESIDENT_FLAGS)):
            self.defines = defines
            self.build_images('-'+staging)
            build = self.report['builds'][-1]
            expected = [*defines, 'pvmArm64JitOwnerReceipt']
            command = build['run']['command']
            actual = [arg for arg in command if arg.startswith('-d:')]
            commands.append([arg for arg in command if arg != '-d:'+RESIDENT_PROOF
                             and not arg.startswith(('--nimcache:', '--out:'))])
            if build['defines'] != expected or actual != ['-d:release', *('-d:'+flag for flag in expected)]:
                raise ValueError('Resident pair image command/profile disagreement')
            self.report['images'][staging] = build
            self.checkpoint()
        self.defines = qualified
        if commands[0] != commands[1]:
            raise ValueError('Resident pair build commands differ beyond selector and output paths')
        if self.report['images'][STACK]['binary_sha256'] == self.report['images'][RESIDENT]['binary_sha256']:
            raise ValueError('Resident pair binaries must be distinct')

    def select(self, staging):
        self.staging = staging
        self.log_prefix = staging+'-'
        if staging != 'reference':
            self.images['doom'] = Path(self.report['images'][staging]['binary'])

    def qualify_controls(self):
        for case in self.cases:
            for staging in (STACK, RESIDENT, 'reference'):
                self.select(staging)
                for role in (('reference',) if staging == 'reference' else ('jit', 'interpreted')):
                    before = len(self.report['controls'])
                    self.controls(case, role)
                    for row in self.report['controls'][before:]:
                        row['staging'] = staging
        self.checkpoint()

    def measure(self, case):
        start = len(self.report['runs'])
        for index, (role, staging) in enumerate(SCHEDULE):
            self.select(staging)
            args, env, _ = self.invocation(case, role)
            image = self.report['images'][staging]
            if str(args[0]) != image['binary'] or self.seals.get(args[0]) != image['binary_sha256']:
                raise ValueError('Resident pair invocation lost its sealed image')
            row = self.command(args, f'{case["case_id"]}-{index:02d}-{role}', env)
            parsed = self.parse(row['output'], case, role)[case['case_id']]
            self.report['runs'].append(dict(case_id=case['case_id'], position=index, role=role,
                staging=staging, binary_sha256=image['binary_sha256'], parsed=parsed, run=command_record(row)))
            self.checkpoint()
        return compare_case(self.report['runs'][start:])

    def execute(self):
        self.folder.mkdir(parents=True, exist_ok=True)
        summary = self.folder/'summary.md'
        if (self.folder/'resident-pair.json').exists():
            raise ValueError('Resident pair receipt already exists')
        summary.write_text('Resident DOOM comparison incomplete.\n')
        self.checkpoint()
        try:
            self.qualify()
            if (self.scope != 'doom' or self.report['architecture'] != 'x86_64'
                    or self.report['identity']['ci']['GITHUB_REF'] != RESIDENT_PAIR_REF
                    or self.defines != RESIDENT_FLAGS):
                raise ValueError('Wrong resident pair runner or profile')
            self.prepare_doom()
            if (self.report['identity']['reference_revision'] != FROZEN_REFERENCE
                    or self.seals.get(self.rom) != FROZEN_ROM):
                raise ValueError('Changed qualified DOOM reference or ROM')
            for path, expected in FROZEN_DOOM.items():
                if self.seals.get(self.folder/path) != expected:
                    raise ValueError('Changed qualified DOOM fixture: '+path)
            self.build_pair()
            self.qualify_controls()
            comparisons = {case['case_id']: self.measure(case) for case in self.cases}
            self.verify()
            self.report['identity']['files'] = {str(path): value for path, value in self.seals.items()}
            self.report.update(status='passed', comparisons=comparisons)
            lines = ['# Same-runner x86 DOOM resident comparison', '',
                     '| Case | Clock | Window | Stack first | Resident first | Movement envelope | Result |',
                     '| --- | --- | --- | ---: | ---: | ---: | --- |']
            for case, rows in comparisons.items():
                for row in rows:
                    order = row['median_ratio_by_first']
                    lines.append(f'| {case} | {row["clock"]} | {row["window"]} | {order[STACK]:.4f} | '
                                 f'{order[RESIDENT]:.4f} | {row["observed_envelope_factor"]:.4f} | '
                                 f'{row["verdict"]} |')
            summary.write_text('\n'.join(lines)+'\n')
            self.checkpoint()
        except BaseException as error:
            self.report.update(status='failed', error=str(error))
            summary.write_text('Resident DOOM comparison failed.\n'+str(error).replace('\n', ' ')+'\n')
            self.checkpoint()
            raise
        return self.report
