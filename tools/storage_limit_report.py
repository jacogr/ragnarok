# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Admit complete native memory-ceiling reports by reparsing raw probes, commands and namespaces."""
import json
from pathlib import Path
from storage_resource_validation import validate_build,validate_checks
from storage_environment import validate_environment
from storage_fresh_reopen import parse_prepared,parse_reopened
from storage_limit_budget import CAPS
from storage_limit_plan import CASES,PHASES,POLICY,phases
from storage_limit_probe import __file__ as PROBE
from storage_limit_provenance import SOURCE,validate_identity
from storage_limit_host import validate_snapshot
from storage_limit_namespace import validate_hashes
from storage_limit_receipts import validate_probe
from storage_limit_supervision import validate_execution


def equal(left,right):
    """Canonical JSON comparison preserves boolean/integer and list/tuple distinctions."""
    return json.dumps(left,sort_keys=True)==json.dumps(right,sort_keys=True)


def validate(report):
    """A completed experiment may contain unavailable or refused caps; every control must fully reopen."""
    expected={'status','schema_version','policy','phases','checks','probes','rows','environment','context_before','context_after','identity'}
    if type(report) is not dict or set(report)!=expected or report['status']!='checks-passed' or type(report['schema_version']) is not int or report['schema_version']!=1 or report['policy']!=POLICY or not equal(report['phases'],phases()):
        raise ValueError('Invalid memory ceiling report status/schema/plan')
    provenance=validate_identity(report['identity']);interpreter=provenance['inputs']['python_identity']['executable']
    validate_environment(report['environment']);system=provenance['host']['system']
    for context in (report['context_before'],report['context_after']):
        validate_snapshot(context)
        if context['system']!=system:
            raise ValueError('Memory context host differs from execution host')
    checks=report['checks']
    if type(checks) is not list or not checks:
        raise ValueError('Missing memory ceiling checked build')
    validate_checks([checks[0]],1);binary=validate_build(checks[0],SOURCE,())
    ordered=[checks[0]];probes=report['probes']
    if type(probes) is not list or len(probes)!=len(CAPS):
        raise ValueError('Incomplete memory ceiling probes')
    for cap,row in zip(CAPS,probes):
        if type(row) is not dict or set(row)!= {'cap','check','raw','observed'} or type(row['cap']) is not int or row['cap']!=cap or type(row['raw']) is not str:
            raise ValueError('Invalid memory ceiling probe identity')
        observed=validate_probe(json.loads(row['raw']),cap)
        if not equal(observed,row['observed']) or observed['limit']['system']!=system:
            raise ValueError('Substituted memory ceiling probe')
        validate_checks([row['check']],1)
        if row['check']['command']!=[interpreter,str(PROBE),str(cap)]:
            raise ValueError('Substituted memory ceiling probe command')
        ordered.append(row['check'])
    rows=report['rows']
    if type(rows) is not list or len(rows)!=len(CASES):
        raise ValueError('Incomplete native memory ceiling coverage')
    namespaces=set()
    for (backend,count),row in zip(CASES,rows):
        if type(row) is not dict or set(row)!= {'case','owned','root','prepared','prepared_raw','selected','attempts'} or not equal(row['case'],[backend,count]):
            raise ValueError('Invalid native memory ceiling case identity')
        owned=row['owned']
        if type(owned) is not str or not Path(owned).is_absolute() or owned in namespaces:
            raise ValueError('Invalid or reused memory experiment namespace')
        namespaces.add(owned);root=parse_prepared(row['prepared_raw'],backend,count)
        if row['root']!=root:
            raise ValueError('Foreign memory experiment root')
        prepared=row['prepared'];validate_checks([prepared],1)
        if prepared['command']!=[binary,'prepare',backend,str(count),owned]:
            raise ValueError('Substituted memory experiment producer')
        ordered.append(prepared);before=validate_hashes(row['selected'],backend)
        attempts=row['attempts']
        if type(attempts) is not list or len(attempts)!=len(PHASES):
            raise ValueError('Incomplete memory ceiling phases')
        reference=None
        for (name,cap),attempt in zip(PHASES,attempts):
            if type(attempt) is not dict or attempt.get('name')!=name or not equal(attempt.get('cap'),cap):
                raise ValueError('Invalid memory ceiling phase identity')
            if not equal(validate_hashes(attempt.get('selected_after'),backend),before):
                raise ValueError('Memory ceiling phase changed selected bytes')
            probe=next((p['observed'] for p in probes if p['cap']==cap),None)
            if cap is not None and probe['status']!='enforced':
                if set(attempt)!= {'name','cap','outcome','reason','selected_after'} or attempt['outcome']!='unavailable' or attempt['reason']!='probe-'+probe['status']:
                    raise ValueError('Unproven cap was executed or availability was hidden')
                continue
            execution=validate_execution(attempt.get('execution'),[binary,'open',backend,str(count),owned,root],cap,interpreter)
            ordered.append(execution['check']);outcome=execution['outcome']
            if execution['receipt_path']!=str(Path(owned)/f'{backend}-{count}-{name}.json') or execution['observation']['limit']['system']!=system or attempt.get('outcome')!=outcome:
                raise ValueError('Substituted limited native receipt identity')
            expected_fields={'name','cap','outcome','execution','selected_after'}|({'native'} if outcome=='completed' else set())
            if set(attempt)!=expected_fields or outcome=='unavailable' or (cap is None and outcome!='completed'):
                raise ValueError('Invalid limited native result or failed unrestricted control')
            if outcome=='completed':
                native=parse_reopened(execution['raw'],backend,count,root)
                if not equal(native,attempt['native']):
                    raise ValueError('Substituted native complete-map witnesses')
                physical={key:native[key] for key in ('stored_nodes','checks')}
                if reference is not None and physical!=reference:
                    raise ValueError('Native physical work differs under ceiling')
                reference=physical
    if not equal(checks,ordered):
        raise ValueError('Memory ceiling check ordering or coverage differs')
    validate_checks(checks,len(ordered))
    return rows
