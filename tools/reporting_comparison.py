# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare each complete reporting chain within the existing runtime budget and bind the complete aggregate output."""
import hashlib
from corpus_checks import compare_corpus


def partition(requests, expected, chains):
    """Require exact scenario-to-observation framing before any chain is executed."""
    result=[];offset=0
    for request in requests:
        fields=request.split()
        assert fields and fields[0] in ('C','B','N','S','T')
        if fields[0]=='C':
            assert len(fields) in (4,5) and offset<len(expected) and expected[offset]=='P '+fields[3]
            result.append(([],[]));size=1
        elif fields[0]=='T':
            assert result and len(fields)==2 and offset+4<len(expected)
            assert expected[offset].startswith('B ') and expected[offset+4].startswith('O ')
            assert expected[offset+1:offset+4]==['R PreStateMismatch','R PostStateMismatch','R CandidateFailure']
            size=5
        elif fields[0] in ('B','S'):
            assert result and len(fields)==(3 if fields[0]=='S' else 2) and offset+1<len(expected)
            assert expected[offset]=='B '+fields[1] and expected[offset+1].startswith('O ')
            size=2
            if fields[0]=='S':
                assert expected[offset+2:offset+5]==['K RootMismatch','K LimitExceeded','K Restored']
                size=5
        else:
            assert result and len(fields)==3 and offset<len(expected) and expected[offset]=='N '+fields[2]
            size=1
        result[-1][0].append(request);result[-1][1].extend(expected[offset:offset+size]);offset+=size
    assert len(result)==chains>0 and offset==len(expected)
    assert all(any(line.startswith(('B ','S ','T ')) for line in group[0]) for group in result)
    return result


def compare_chains(result,command,binary,fixture,source,requests,expected,chains):
    """Keep strict per-process verdicts and complete actual/expected hashes; partial execution cannot pass."""
    groups=partition(requests,expected,chains)
    if result['build']['exit_code']!=0: return
    observed=[];runs=[]
    for index,(inputs,answers) in enumerate(groups):
        child_source=source.with_name(source.stem+'-chain-'+str(index)+source.suffix)
        child_source.write_text('\n'.join(inputs)+'\n')
        child=dict(build=result['build'],passed=False)
        def capture(arguments,name):
            """Retain exact stdout before the common comparator consumes its process payload."""
            outcome=command(arguments,name);observed.append(outcome['output']);return outcome
        compare_corpus(child,capture,[binary,fixture,child_source],source.stem+'-chain-'+str(index),answers)
        runs.append({k:v for k,v in child.items() if k!='build'})
    output=''.join(observed);actual=output.splitlines()
    result.update(passed=len(runs)==chains and all(r['passed'] for r in runs) and actual==expected,
        runs=runs,actual_sha256=hashlib.sha256(output.encode()).hexdigest(),
        expected_sha256=hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest())
    if not result['passed']:
        result['first_mismatch']=next((i for i,(a,e) in enumerate(zip(actual,expected)) if a!=e),min(len(actual),len(expected)))
