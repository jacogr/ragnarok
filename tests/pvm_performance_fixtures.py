# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Independently authored canonical observations for report and authenticated retrieval tests."""
import copy

REVISION = 'a'*40
REFERENCE = 'b'*40
SYNTHETICS = ('arithmetic-10000', 'memory-aligned-1000', 'memory-crossing-1000',
    'hosts-aligned-1000', 'hosts-crossing-1000', 'arithmetic-1', 'arithmetic-16',
    'bits-mixed-1000', 'sparse-aligned-1000', 'sparse-crossing-1000', 'blocks-alternating-1000')
GUESTS = (('sieve', 1000), ('sieve', 10000), ('sieve', 100000), ('sieve', 10000000),
          ('minimal', 1000), ('minimal', 100000), ('memset', 1000), ('memset', 100000), ('pinky', 1))


def retained_instance(label):
    """Independent literal observations include zero initial code and subsequent retained growth."""
    return dict(version=1, label=label, instances=1, constructor_cpu_ns=11,
        constructor_wall_ns=17, initial_cache_bytes=0, teardown_cpu_ns=3, teardown_wall_ns=7,
        samples=[dict(sample=i, restore_cpu_ns=10, restore_wall_ns=20,
            before_reset_bytes=0 if i == 0 else 64+8*(i-1),
            after_reset_bytes=0 if i == 0 else 64+8*(i-1), after_run_bytes=64+8*i)
            for i in range(13)])


def lifetime_wire(label):
    """Encode fixture observations explicitly, independently of the production receipt parser."""
    lines = [f'REFERENCE_INSTANCE,1,{label},11,17,0']
    for i in range(13):
        before = 0 if i == 0 else 64+8*(i-1)
        lines += [f'REFERENCE_RESTORE,1,{label},{i},10,20',
                  f'REFERENCE_CACHE,1,{label},{i},{before},{before},{64+8*i}']
    return '\n'.join([*lines, f'REFERENCE_INSTANCE_DROP,1,{label},3,7'])+'\n'


def observations(scope='all', architecture='arm64', run_id='100', attempt='1'):
    """Build literal positive processes without computing expectations through the report module."""
    cases = []
    if scope != 'doom':
        cases += [(name, name, 0, 'synthetic') for name in SYNTHETICS]
        cases += [(f'{name}-{limit}', name, limit, 'guest') for name, limit in GUESTS]
    if scope != 'micro':
        cases += [('doom-init', 'init', 0, 'doom'), ('doom-tick', 'tick', 0, 'doom')]
    families = sorted({row[3] for row in cases})
    files = {'/sealed/src/pvm/step.nim': '1'*64, '/sealed/compiler/nimony': '2'*64,
             '/sealed/build/tests/pvm-native/results.json': '3'*64, '/sealed/input.bin': '4'*64}
    for index, family in enumerate(families):
        files['/sealed/current-'+family] = str(index+5)*64
        files['/sealed/reference-'+family] = hex(index+10)[2:]*64
    machine, runner, define = ('aarch64', 'ARM64', 'pvmArm64Jit') if architecture == 'arm64' else (
        'x86_64', 'X64', 'pvmX86Jit')
    identity = dict(host=dict(system='Linux', machine=machine, uname=['Linux', machine],
        architecture=architecture, cpu='independent native fixture', runner=dict(RUNNER_ARCH=runner)),
        ci=dict(GITHUB_RUN_ID=run_id, GITHUB_RUN_ATTEMPT=attempt, GITHUB_EVENT_NAME='push',
            GITHUB_REF='refs/heads/master', GITHUB_SHA=REVISION, GITHUB_REPOSITORY='jacogr/ragnarok',
            GITHUB_JOB='pvm-comparison', PVM_CI_JOB_NAME='Independent PVM fixture '+architecture),
        compiler=dict(sha256='2'*64, identity='pinned compiler'), files=files,
        native_qualification=dict(path='build/tests/pvm-native/results.json', sha256='3'*64,
            revision=REVISION), native_build_defines=[define], toolchain=dict(commit='c'*40),
        reference_revision=REFERENCE, doom_warmup_ticks=1320, code_lifetime='retained-code-v1',
        doom=dict(warmup_ticks=1320, golden_rgba_sha256='d'*64))
    report = dict(schema='pvm-performance-v2', status='passed', revision=REVISION,
                  architecture=architecture, scope=scope, identity=identity, runs=[], controls=[], builds=[])
    for family in families:
        report['builds'].append(dict(family=family, binary='/sealed/current-'+family,
            binary_sha256=files['/sealed/current-'+family], defines=[define]+([] if family == 'synthetic'
                else ['pvmArm64JitOwnerReceipt']), run=dict(exit_code=0)))
    for order, roles in enumerate((('interpreted', 'jit', 'reference'), ('reference', 'jit', 'interpreted'))):
        for case_id, case, limit, family in cases:
            for role in roles:
                # Independent clocks/orders and deliberately expensive discarded samples prevent pooling.
                base = dict(interpreted=200, jit=100, reference=50)[role]*(order+1)
                samples = [dict(sample=i, cpu_ns=base+(10000 if i in (1, 2) else i),
                    wall_ns=base*3+(20000 if i in (1, 2) else i*2)) for i in range(13)]
                execution = dict(samples=samples, preparation_ns=[base*10],
                                 preparation_wall_ns=[base*20])
                native, policy = None, None
                if role != 'reference':
                    # Tiny optional cases exercise genuine checked fallback; mandatory cells retain native work.
                    required = case_id in ('sieve-10000000', 'doom-init', 'doom-tick')
                    active = role == 'jit' and required
                    native = dict(fragments=1 if active else 0, calls=13 if active else 0,
                        operations=130 if active else 0, code_bytes=40 if active else 0,
                        compilation_ns=10 if active else 0)
                    policy = dict(version=1, requested=role, actual='jit' if active else 'interpreted',
                        jit_built=True, platform_supported=True, fallback_enabled=role == 'jit',
                        **{key: native[key] for key in ('fragments', 'calls', 'operations')})
                if role == 'reference':
                    label = 'synthetic-'+str(SYNTHETICS.index(case_id)) if family == 'synthetic' else case_id
                    execution['reference_instance'] = retained_instance(label)
                binary = '/sealed/'+('reference-' if role == 'reference' else 'current-')+family
                run = dict(command=[binary, case_id], log=f'logs/{case_id}-{role}-{order}.log', exit_code=0)
                report['runs'].append(dict(case_id=case_id, case=case, limit=limit, role=role,
                    order=order, parsed=dict(execution=execution, native=native, policy=policy), run=run))
    control_cases = [(row[0], row[3]) for row in cases if row[3] != 'synthetic']
    if scope != 'doom':
        control_cases.insert(0, ('synthetic', 'synthetic'))
    for case_id, family in control_cases:
        for role in ('interpreted', 'jit', 'reference'):
            for kind in ('positive', 'assertions', 'state', 'events') if family == 'doom' else (
                    'positive', 'assertions', 'state'):
                binary = '/sealed/'+('reference-' if role == 'reference' else 'current-')+family
                report['controls'].append(dict(case_id=case_id, role=role, kind=kind,
                    run=dict(command=[binary], log=f'logs/{case_id}-{role}-{kind}.log',
                             exit_code=0 if kind == 'positive' else 1)))
    return copy.deepcopy(report)
