# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Measure opt-in Contract bundles against their standalone fixtures in independent cold caches."""
from pathlib import Path
from native_checks import NativeChecks
from failure_checks import FAILURE_SUITES, run_failure_suite, run_failure_suites, case_details


def measure(compiler, folder, libraries, members):
    """Use two counterbalanced orderings, exact negative probes and original positive fixture modes."""
    passes = []
    for repeat, ordering in enumerate((('standalone', 'bundled'), ('bundled', 'standalone'))):
        for mode in ordering:
            workspace = Path(folder)/('pair-'+str(repeat))/mode
            workspace.mkdir(parents=True, exist_ok=True)
            checks = NativeChecks(workspace, reuse_builds=True, lto=False)
            report = {group: [] for group in members}
            binaries = {}
            def build(*arguments, **options):
                """Remember the compiled outputs for independent positive-control children."""
                compiled, binary = checks.build(*arguments, **options)
                binaries[arguments[2]] = binary
                return compiled, binary
            if mode == 'standalone':
                for group in members:
                    run_failure_suite(compiler, report, libraries, build, checks.command, group)
            else:
                run_failure_suites(compiler, report, libraries, build, checks.command,
                                   groups=members, folder=workspace)
            # A faster unrelated failure is never a performance result.
            for group in members:
                expected = [case_details(FAILURE_SUITES[group], case)['identity'] for case in FAILURE_SUITES[group]['cases']]
                observed = [{k:v for k,v in row.items() if k not in ('run','passed')} for row in report[group]]
                if observed != expected or not all(row['passed'] for row in report[group]):
                    raise ValueError('Invalid measured Contract rejection: '+group)
            # These original successful modes must also survive standalone and module-dispatch execution.
            controls = []
            for group, selection in (('pvm_step', 'negative'), ('pvm_gas', 'negative'),
                                     ('pvm_fallthrough', 'valid')):
                name = FAILURE_SUITES[group]['build_name'] if mode == 'standalone' else 'failure-bundle-pvm-core'
                arguments = [binaries[name], selection] + ([group] if mode == 'bundled' else [])
                checked = checks.command(arguments, group+'-positive')
                controls.append(dict(family=group, selection=selection, run=checked))
                if checked['exit_code'] != 0 or checked['output'].strip():
                    raise ValueError('Invalid measured Contract positive control: '+group)
            report['positive_controls'] = controls
            builds = [report[group+'_build'] for group in members]
            passes.append(dict(pair=repeat, mode=mode, cache='fresh-private-intermediates',
                build_seconds=sum(row['elapsed_seconds'] for row in builds),
                executable_builds=sum(not row.get('reused', False) for row in builds),
                probe_seconds=sum(row['run']['elapsed_seconds'] for group in members for row in report[group])
                    +sum(row['run']['elapsed_seconds'] for row in controls),
                probes=sum(len(report[group]) for group in members), positive_controls=len(controls), evidence=report))
    return passes
