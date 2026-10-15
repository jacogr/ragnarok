#!/usr/bin/env python3
"""Prospective task journal: retain compiler/test attempts and separately attributed human findings."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
from measure import ROOT, environment

CAUSES = ('language', 'compiler', 'logic', 'library', 'ffi', 'infrastructure', 'unknown')


# UTC timestamps measure wall-clock development latency, including pauses and human response time.
def now():
    return datetime.now(timezone.utc).isoformat()


# Snapshot preregistered implementation/test paths so stale passing checks cannot finish a changed task.
def sources(plan, language):
    result = {}
    root = ROOT.resolve()
    # Do not silently add build artifacts or change scope between candidates.
    for name in plan['source_paths'][language]:
        path = (root/name).resolve()
        # Keep accidental broad scopes and unrelated files out of task evidence.
        if not path.is_relative_to(root) or path == root or path.relative_to(root).parts[0] in ('build', '.git'):
            raise ValueError('Source paths must be project sources outside build/.git')
        # A misspelled scope must not silently omit implementation from its fingerprints.
        if not path.exists():
            raise ValueError(f'Missing registered source path: {name}')
        files = [path] if path.is_file() else sorted(path.rglob('*'))
        # Inspect each actual source owner before recording its current bytes.
        for source in files:
            # Generated Python bytecode is not an implementation edit.
            if source.is_file() and '__pycache__' not in source.parts:
                result[str(source.relative_to(root))] = hashlib.sha256(source.read_bytes()).hexdigest()
    # A nonexistent/empty scope cannot establish equivalent task completion.
    if not result:
        raise ValueError('No registered source files')
    return result


# Write each completed event atomically; one agent/controller owns each task journal.
def save(path, state):
    # The contract may not be rewritten after seeing a candidate's outcome.
    if hashlib.sha256(json.dumps(state['plan'], sort_keys=True).encode()).hexdigest() != state['plan_sha256']:
        raise ValueError('The preregistered plan changed; start a separate trial')
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.pending')
    temporary.write_text(json.dumps(state, indent=2)+'\n')
    temporary.replace(path)


# Register the equivalent contract and assistance settings before the first implementation edit.
def begin(path, plan, language):
    # An earlier trial is evidence even when it was unsuccessful or incomplete.
    if path.exists():
        raise ValueError('Refusing to overwrite an existing journal')
    required = ('equivalence_id', 'functionality', 'acceptance', 'baseline', 'source_paths',
                'configuration', 'agent', 'task_order', 'specification')
    # Reject a missing contract before starting a comparison clock.
    if any(not plan.get(key) for key in required if key != 'baseline') or 'baseline' not in plan:
        raise ValueError('Incomplete preregistration; use the documented plan schema')
    # Every acceptance/baseline check needs a concrete command for all three candidates.
    for group in ('acceptance', 'baseline'):
        # Each registered behavior needs corresponding concrete commands across candidates.
        for check, commands in plan[group].items():
            # A missing language/command would make task completion incomparable.
            if set(commands) != {'nim', 'odin', 'mojo'} or any(not isinstance(command, list) or not command for command in commands.values()):
                raise ValueError(f'Incomplete {group} command: {check}')
    state = {'schema': 1, 'journal_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'started_at': now(), 'language': language, 'plan': json.loads(json.dumps(plan)),
             'plan_sha256': hashlib.sha256(json.dumps(plan, sort_keys=True).encode()).hexdigest(),
             'environment': environment(), 'initial_sources': sources(plan, language), 'events': []}
    save(path, state)
    return state


# Record one actual invocation; intentional rejection probes cannot count as implementation failures/repairs.
def run(path, state, phase, check, command, cause, repair_of, timeout, repair_note=None):
    # A completed history cannot accept additional attempts retroactively.
    if 'finished_at' in state:
        raise ValueError('The trial is already finished')
    # Acceptance and baseline commands come from the frozen contract.
    if phase in ('acceptance', 'baseline', 'recheck'):
        group = 'baseline' if phase in ('baseline', 'recheck') else 'acceptance'
        # Do not permit a caller to substitute a weaker check at execution time.
        if command or check not in state['plan'][group]:
            raise ValueError('Use a registered check, with no command override')
        command = state['plan'][group][check][state['language']]
        # Regressions require an observed passing baseline, not an assumed green starting revision.
        if phase == 'recheck' and not any(e.get('phase') == 'baseline' and e.get('check') == check and e.get('status') == 'passed' for e in state['events']):
            raise ValueError('No passing baseline for this check')
    # A compiler attempt needs its exact executable and arguments for reproduction.
    elif not command:
        raise ValueError('A direct compiler/diagnostic command is required')
    # Only explicitly declared fixes count as repair cycles.
    if repair_of:
        # Declared fix intent distinguishes a repair from an unchanged retry or intentional rejection.
        if not repair_note:
            raise ValueError('A repair requires a note describing the actual source/configuration fix')
        prior = next((e for e in state['events'] if e['id'] == repair_of), None)
        # A deliberate rejection or successful build cannot be the failed half of a repair.
        if phase != 'compile' or not prior or prior.get('phase') != 'compile' or prior['status'] != 'failed':
            raise ValueError('A repair must reference a failed nonintentional compiler attempt')
    # One failed attempt must not be charged repeatedly for the same linked repair.
    if repair_of and any(e.get('repair_of') == repair_of for e in state['events']):
        raise ValueError('This failed attempt already has its recorded repair')
    # Establish old passing behavior before implementation changes can obscure its baseline.
    if phase == 'baseline' and sources(state['plan'], state['language']) != state['initial_sources']:
        raise ValueError('The passing baseline must precede implementation edits')
    number = len(state['events']) + 1
    log = path.parent/f'{path.stem}-{number:04d}.log'
    event = {'id': f'e{number}', 'kind': 'run', 'phase': phase, 'check': check, 'cause': cause,
             'repair_of': repair_of, 'repair_note': repair_note, 'command': command, 'started_at': now(),
             'sources': sources(state['plan'], state['language']), 'log': str(log)}
    # Preserve the in-progress attempt even if this controller itself is interrupted.
    event['status'] = 'running'
    state['events'].append(event)
    save(path, state)
    # Persist combined compiler/test output before exposing the final event status.
    with log.open('wb') as output:
        # Tool launch failures require different attribution from compiler rejection.
        try:
            process = subprocess.Popen(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                       start_new_session=True, env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
        # Record a missing executable as infrastructure and retain its diagnostic.
        except OSError as error:
            # Missing tools are infrastructure failures, not rejected implementation code.
            output.write(str(error).encode())
            event.update(returncode=None, status='launch_error', cause='infrastructure', launched=False)
        else:
            event['launched'] = True
            # Bound the actual command without hiding its exit status or a timeout.
            try:
                code = process.wait(timeout=timeout)
                event.update(returncode=code, status='passed' if code == 0 else 'failed')
            # An unresponsive command must not leave child compilers running after timeout.
            except subprocess.TimeoutExpired:
                # Reap the compiler's child group too; a timeout is not automatically a source-repair verdict.
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                event.update(returncode=None, status='timeout')
    event.update(ended_at=now(), log_sha256=hashlib.sha256(log.read_bytes()).hexdigest())
    save(path, state)
    return event


# Record distinct reviewed findings; failing assertions are not automatically counted as distinct defects.
def annotate(path, state, kind, identifier, cause, note, evidence, run_id=None):
    # Preserve original event identities and prohibit annotations after trial completion.
    if 'finished_at' in state or any(e['id'] == identifier for e in state['events']):
        raise ValueError('Finished journal or duplicate event ID')
    referenced = next((e for e in state['events'] if e['id'] == run_id), None)
    # Attribution must refer to an observable command, not a fabricated incident.
    if kind == 'attribution' and (not referenced or referenced['kind'] != 'run'):
        raise ValueError('Attribution requires an existing run ID')
    # The metric excludes findings made before any successful build.
    if kind == 'defect' and not any(e.get('phase') == 'compile' and e['status'] == 'passed' for e in state['events']):
        raise ValueError('Post-compilation defect requires a prior successful build')
    # A regression claim needs both an earlier pass and a concrete failed recheck.
    if kind == 'regression' and (not referenced or referenced.get('phase') != 'recheck' or referenced['status'] != 'failed'):
        raise ValueError('A confirmed regression must reference a failed rerun of a passing baseline')
    state['events'].append({'id': identifier, 'kind': kind, 'cause': cause, 'note': note,
                            'evidence': evidence, 'run_id': run_id, 'recorded_at': now()})
    save(path, state)


# Complete only when every equivalent acceptance check passes on the current registered source snapshot.
def finish(path, state, annotations_complete, attempts_complete=False, loc_snapshot=None):
    # Completion is a single historical boundary rather than an editable score.
    if 'finished_at' in state:
        raise ValueError('The trial is already finished')
    # An interrupted controller leaves an evidence gap that needs investigation.
    if any(e.get('status') == 'running' for e in state['events']):
        raise ValueError('Interrupted attempt requires explicit investigation before completion')
    current = sources(state['plan'], state['language'])
    compiled = [e for e in state['events'] if e.get('phase') == 'compile' and e.get('status') == 'passed' and e['sources'] == current]
    # Do not finish with a build from older source bytes.
    if not compiled:
        raise ValueError('No successful build on current sources')
    passing = []
    # Each check must have a passing final invocation, not just an earlier transient pass.
    for check in state['plan']['acceptance']:
        attempts = [e for e in state['events'] if e.get('phase') == 'acceptance' and e['check'] == check]
        # A stale or subsequently failing check cannot certify the current implementation.
        if not attempts or attempts[-1]['status'] != 'passed' or attempts[-1]['sources'] != current:
            raise ValueError(f'Missing current passing acceptance: {check}')
        passing.append(attempts[-1])
    statuses, end = {}, None
    # Repeated verification must not inflate time-to-first-green; preserve the earliest complete passing frontier.
    for event in state['events']:
        # Only acceptance results for the final source snapshot contribute to its first green frontier.
        if event.get('phase') == 'acceptance' and event.get('sources') == current:
            statuses[event['check']] = event['status']
            # Capture the first point at which every registered behavior was passing.
            if end is None and all(statuses.get(check) == 'passed' for check in state['plan']['acceptance']):
                end = event['ended_at']
    # No observed complete acceptance pass means development time is unavailable.
    if end is None:
        raise ValueError('No complete passing acceptance frontier')
    elapsed = (datetime.fromisoformat(end)-datetime.fromisoformat(state['started_at'])).total_seconds()
    rechecks = {e['check'] for e in state['events'] if e.get('phase') == 'recheck' and e.get('status') in ('passed', 'failed')}
    failures = {e['check'] for e in state['events'] if e.get('phase') == 'recheck' and e.get('status') == 'failed'}
    regressions = {next(run for run in state['events'] if run['id'] == e['run_id'])['check'] for e in state['events'] if e['kind'] == 'regression'}
    repairs = {cause: 0 for cause in CAUSES}
    # Explicit post-diagnostic attribution supersedes the initial unknown/best-effort category, retaining both.
    for event in state['events']:
        # Attribute each declared fix through the failure it actually repaired.
        if event.get('repair_of'):
            prior = next(e for e in state['events'] if e['id'] == event['repair_of'])
            cause = prior['cause']
            # Retain later evidence-based cause corrections without rewriting the original event.
            for annotation in state['events']:
                # Only explicit attribution events can supersede a command's original category.
                if annotation['kind'] == 'attribution' and annotation['run_id'] == prior['id']:
                    cause = annotation['cause']
            repairs[cause] += 1
    implementation_loc = None
    # Optional LOC evidence remains N/A until measured against current sources.
    if loc_snapshot is not None:
        # LOC evidence must describe this language's current preregistered files, never an older implementation.
        audit = json.loads(loc_snapshot.read_text())
        files = [item for item in audit['files'] if item['language'] == state['language']]
        # Reject an older or unrelated file set even if its aggregate count looks plausible.
        if not files or any(current.get(item['path']) != item['sha256'] for item in files):
            raise ValueError('LOC snapshot is stale or outside registered source scope')
        implementation_loc = sum(item['implementation_loc'] for item in files)
        state['loc_evidence'] = {'path':str(loc_snapshot), 'sha256':hashlib.sha256(loc_snapshot.read_bytes()).hexdigest(),
                                 'definition':audit['definition']}
    state['final_journal_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    state['final_environment'] = environment()
    state['environment_drift'] = {key:state['environment'].get(key) != state['final_environment'].get(key)
                                  for key in ('tools', 'configuration_sha256')}
    state['first_passing_tests_at'] = end
    state['finished_at'] = now()
    # Unreviewed manual annotation coverage stays N/A, including an empty interventions/defects ledger.
    state['metrics'] = {'compiler_repair_iterations': sum(repairs.values()) if attempts_complete else None,
                        'observed_compiler_repairs_by_cause': repairs,
                        'direct_compile_invocations': sum(e.get('phase') == 'compile' and e.get('launched', False) for e in state['events']),
                        'attempts_complete': attempts_complete,
                        'time_to_passing_tests_seconds': elapsed if elapsed >= 0 and attempts_complete else None,
                        'observed_time_to_logged_passing_tests_seconds': elapsed if elapsed >= 0 else None,
                        'bugs_found_after_compilation': sum(e['kind'] == 'defect' for e in state['events']) if annotations_complete else None,
                        'human_interventions': sum(e['kind'] == 'intervention' for e in state['events']) if annotations_complete else None,
                        'confirmed_regression_checks': len(regressions) if annotations_complete else None,
                        'baseline_checks_retested': len(rechecks), 'baseline_checks_registered': len(state['plan']['baseline']),
                        'regression_rate': len(regressions)/len(rechecks) if annotations_complete and rechecks else None,
                        'raw_recheck_failure_rate': len(failures)/len(rechecks) if rechecks else None,
                        'annotations_complete': annotations_complete,
                        'compiler_attempt_capture': 'operator must attest all direct attempts were wrapped; interruptions remain visible',
                        'implementation_loc': implementation_loc}
    save(path, state)
    return state['metrics']


# Keep the CLI explicit: no periodic work, background feature increment or historical data fabrication.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('begin', 'run', 'event', 'finish'))
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--plan', type=Path)
    parser.add_argument('--language', choices=('nim', 'odin', 'mojo'))
    parser.add_argument('--phase', choices=('compile', 'acceptance', 'baseline', 'recheck', 'diagnostic'))
    parser.add_argument('--check')
    parser.add_argument('--cause', choices=CAUSES, default='unknown')
    parser.add_argument('--repair-of')
    parser.add_argument('--repair-note')
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--kind', choices=('defect', 'finding', 'intervention', 'regression', 'attribution'))
    parser.add_argument('--id')
    parser.add_argument('--note')
    parser.add_argument('--evidence')
    parser.add_argument('--run-id')
    parser.add_argument('--annotations-complete', action='store_true')
    parser.add_argument('--attempts-complete', action='store_true')
    parser.add_argument('--loc-snapshot', type=Path)
    raw = sys.argv[1:]
    # Only the explicit separator introduces a compiler command; ordinary options remain parser options.
    boundary = raw.index('--') if '--' in raw else len(raw)
    command = raw[boundary+1:]
    args = parser.parse_args(raw[:boundary])
    # Registration starts a new task rather than executing implementation commands.
    if args.operation == 'begin':
        # Task scope and candidate identity are necessary before measuring elapsed work.
        if args.plan is None or args.language is None:
            parser.error('begin requires --plan and --language')
        begin(args.state, json.loads(args.plan.read_text()), args.language)
        return
    state = json.loads(args.state.read_text())
    # Execution records exact commands and their original result.
    if args.operation == 'run':
        # A command needs an explicit measurement role to avoid mixing probes with repairs.
        if args.phase is None:
            parser.error('run requires --phase')
        event = run(args.state, state, args.phase, args.check, command, args.cause, args.repair_of, args.timeout, args.repair_note)
        print(json.dumps(event, indent=2))
        sys.exit(0 if event['status'] == 'passed' else 1)
    # Reviewed observations are separate from automatic command events.
    elif args.operation == 'event':
        # Every manual count needs a stable ID, explanation and supporting evidence.
        if not all((args.kind, args.id, args.note, args.evidence)):
            parser.error('event requires --kind, --id, --note and --evidence')
        annotate(args.state, state, args.kind, args.id, args.cause, args.note, args.evidence, args.run_id)
    else:
        print(json.dumps(finish(args.state, state, args.annotations_complete, args.attempts_complete, args.loc_snapshot), indent=2))


# Importing bookkeeping functions executes no compiler, test or task.
if __name__ == '__main__':
    main()
