# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare admitted matching memory-ceiling experiments without causal RSS or speed claims."""
import argparse
import json
from pathlib import Path
from storage_benchmark import atomic_text
from storage_limit_report import validate


def compare(baseline,candidate):
    """Require identical source/build/host/environment and cap support before descriptive paired observations."""
    for report in (baseline,candidate):
        validate(report)
        if report['identity']['inputs']['dirty'] is not False:
            raise ValueError('Memory ceiling comparison requires clean-source reports')
    for key in ('host','native_binary_sha256'):
        if baseline['identity'][key]!=candidate['identity'][key]:
            raise ValueError('Memory ceiling binary/host differs')
    for key in ('sources','compiler_sha256','native_components','clang','toolchain','python_identity'):
        if baseline['identity']['inputs'][key]!=candidate['identity']['inputs'][key]:
            raise ValueError('Memory ceiling source/build differs')
    for key in ('cache_policy','block_bytes','fragment_bytes','capacity_bytes','device_id','read_only','physical_memory_bytes','inherited_limits'):
        if baseline['environment'][key]!=candidate['environment'][key]:
            raise ValueError('Memory ceiling filesystem or inherited environment differs')
    for left,right in zip(baseline['probes'],candidate['probes']):
        if left['observed']!=right['observed']:
            raise ValueError('Memory ceiling probe support differs')
    for edge in ('context_before','context_after'):
        a=baseline[edge];b=candidate[edge]
        if a['system']=='Linux':
            x=a['cgroup'];y=b['cgroup']
            if x['status']!=y['status']:
                raise ValueError('Memory ceiling cgroup availability differs')
            if x['status']=='available' and (x['scope']!=y['scope'] or any(x['value'][k]!=y['value'][k] for k in ('memory.max','memory.high','memory.swap.max'))):
                raise ValueError('Memory ceiling cgroup configuration differs')
    lines=['# Matching storage memory ceiling observations','','Identical recorded inputs and binary. RSS values are descriptive independent child peaks; no subtraction, speedup or paging attribution.','',
           '| Backend | Entries | Phase | Outcome | Baseline peak bytes | Candidate peak bytes |',
           '| --- | ---: | --- | --- | ---: | ---: |']
    for a,b in zip(baseline['rows'],candidate['rows']):
        if a['root']!=b['root'] or a['selected']!=b['selected']:
            raise ValueError('Memory ceiling physical namespace differs')
        for x,y in zip(a['attempts'],b['attempts']):
            if x['outcome']!=y['outcome']:
                raise ValueError('Memory ceiling outcomes differ')
            if 'execution' in x:
                if x['execution']['observation']['limit']!=y['execution']['observation']['limit']:
                    raise ValueError('Memory ceiling effective bounds differ')
                if x.get('native',{}).get('stored_nodes')!=y.get('native',{}).get('stored_nodes'):
                    raise ValueError('Memory ceiling physical work differs')
                left=x['execution']['observation']['resources']['peak_rss_bytes'];right=y['execution']['observation']['resources']['peak_rss_bytes']
            else:
                left=right='unavailable'
            lines.append(f'| {a["case"][0]} | {a["case"][1]} | {x["name"]} | {x["outcome"]} | {left} | {right} |')
    return '\n'.join(lines)+'\n'


def main():
    """Invalid comparisons retire only their requested stale public output."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline',type=Path,required=True);parser.add_argument('--candidate',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    args.output.unlink(missing_ok=True)
    text=compare(json.loads(args.baseline.read_text()),json.loads(args.candidate.read_text()))
    args.output.parent.mkdir(parents=True,exist_ok=True);atomic_text(args.output,text)


# Pure comparison never executes paths from imported reports.
if __name__=='__main__':
    main()
