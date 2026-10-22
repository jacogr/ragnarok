# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Author complete panel reports independently for provenance, raw-output and comparison safeguards."""
import hashlib
import json
from pathlib import Path
import platform
import sys
import tempfile
from storage_benchmark import source_hashes, benchmark_sources
import storage_resource_panel as panel
from storage_environment import environment
from test_storage_growth_report import output
from test_storage_deployment_benchmark import output as deployment_output


def fixture(module):
    """Every case has independently authored native output plus a matching checked build/execution receipt."""
    binary = '/fixture/panel-native'
    build = ['/fixture/nimony', 'c', '--mm:arc', '--cc:clang', '-d:release', '--opt:speed', '--boundchecks:on',
             '--passC:-flto', '--passL:-flto', '--passC:-I'+str(panel.ROOT/'native/crypto'),
             '--passL:'+str(panel.ROOT/'build/crypto/libragnarok_crypto.dylib'),
             '--passL:-Wl,-rpath,'+str(panel.ROOT/'build/crypto'),
             *['-d:'+v for v in module.DEFINES], '--nimcache:/fixture/cache', '--out:'+binary, str(module.SOURCE)]
    with tempfile.TemporaryDirectory() as folder:
        observed_environment = environment(folder)
    sources = source_hashes([*benchmark_sources(), *sorted((panel.ROOT/'tools').glob('storage_*.py')),
                             *sorted((panel.ROOT/'tests/support').glob('storage_*.nim')), module.SOURCE])
    python_identity = dict(executable=sys.executable, version=platform.python_version(),
                           sha256=hashlib.sha256(Path(sys.executable).read_bytes()).hexdigest())
    report = dict(status='checks-passed', schema_version=getattr(panel, 'PANEL_VERSION', 2), profile=panel.PROFILE,
        source=str(module.SOURCE), defines=list(module.DEFINES), cases=[list(c) for c in module.CASES],
        native_binary_sha256='a'*64, python_executable=sys.executable, python_identity=python_identity,
        inputs=dict(sources=sources, python_identity=python_identity, head='b'*40, dirty=False, compiler_sha256='c'*64, clang='fixture clang',
                    native_components={k:'d'*64 for k in ('bridge','provider_loader','provider_build')},
                    toolchain=json.loads((panel.ROOT/'spec/toolchain.json').read_text())),
        hardware=dict(platform='fixture platform', machine='fixture machine', cpu='fixture CPU', page_size_bytes=4096),
        environment_start=observed_environment, environment_end=observed_environment,
        checks=[dict(exit_code=0, elapsed_seconds=0.01, command=build, log='build.log')], runs=[])
    for index, case in enumerate(module.CASES):
        # Native witnesses are authored separately from their parser, including explicit unavailable stages.
        if module.__name__ == 'storage_allocation_benchmark':
            _, engine, count = case
            phases = ['fixture','seed','owner','publication','snapshots','extraction','reads']
            if engine != 'memory': phases += ['reopen']
            if engine != 'journal': phases += ['retention','maintenance']
            phases += ['closed']
            raw = ''.join(f'allocation\t{p}\t{(i+1)*100}\n' for i,p in enumerate(phases))
            raw += output(engine,count,64).split(f'publication\t{count}\t64\tsweep\t1\t')[0]
        elif module.__name__ == 'storage_lifetime_benchmark':
            scenario, count = case
            states = {'fixture':(count+64,900,-1,-1,-1), 'owner':(count,-1,900,-1,100),
                      'reader':(count*2,-1,900,900,900), 'readers':(count+4096,-1,900,1100,1100),
                      'extraction':(count,-1,900,1400,500), 'lookups':(count+4096,-1,900,1500,600),
                      'selection':(count,-1,900,1100,1100)}
            checks, fixture_bytes, owner, held, closed = states[scenario]
            raw = f'lifetime\t{scenario}\t{count}\t64\t{checks}\t100\t{fixture_bytes}\t{owner}\t{held}\t{closed}\t100\n'
        else:
            _, engine, count, steps = case
            raw = deployment_output(engine,count,steps)
        owned = '/fixture/owned-'+str(index); counters = owned+'/resources.json'
        resources = dict(peak_rss_bytes=1000000, minor_faults=7, major_faults=0)
        report['runs'].append(dict(case=list(case), owned=owned, counters_path=counters, raw=raw,
                                   observed=module.parse(raw,case), resources=resources))
        report['checks'].append(dict(exit_code=0, elapsed_seconds=0.01, log=str(index)+'.log',
            command=[sys.executable,str(panel.CHILD),counters,binary,*[str(v) for v in module.arguments(case,owned)]]))
    return report
