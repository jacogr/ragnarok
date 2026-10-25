# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Require precise nonzero native inventory refusal with exact pre-installation output and genuine positive corpus controls."""
import hashlib


def compare_inventory_controls(result,command,binary,fixture,source,cases):
    """Neither premature failure, successful installation nor unrelated diagnostics can impersonate an inventory refusal."""
    assert result['passed'] and cases
    actual=[];expected=[];runs=[]
    for case in cases:
        path=source.with_name(source.stem+'-inventory-'+case['name']+'.txt')
        wire='\n'.join(case['requests'])+'\n';path.write_text(wire)
        outcome=command([binary,fixture,path],source.stem+'-inventory-'+case['name'])
        wanted='\n'.join(case['expected'])+'\n'
        passed=outcome['exit_code']!=0 and outcome['output']==wanted
        actual.append(outcome['output']);expected.append(wanted)
        runs.append(dict(name=case['name'],passed=passed,run={k:v for k,v in outcome.items() if k!='output'},
            requests_sha256=hashlib.sha256(wire.encode()).hexdigest()))
    result.update(inventory_refusals=len(cases),inventory_controls=runs,
        inventory_actual_sha256=hashlib.sha256(''.join(actual).encode()).hexdigest(),
        inventory_expected_sha256=hashlib.sha256(''.join(expected).encode()).hexdigest(),
        passed=result['passed'] and len(runs)==len(cases) and all(row['passed'] for row in runs))
