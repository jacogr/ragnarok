# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate complete sieve observations and retain CPU/wall distributions without filtering noise."""
import statistics

ENGINES=('ragnarok','polkavm_interpreter')
LIMITS=(1000,100000)
SAMPLES=13


def parse_output(output,engine,limit):
    """Accept one ordered, complete pass; reject extra output, duplicate and nonpositive samples."""
    if engine not in ENGINES or limit not in LIMITS:
        raise ValueError("Unknown sieve engine or limit")
    rows=[]
    for line in output.splitlines():
        # Native output is a strict protocol, not an opportunistic scan of successful-looking lines.
        fields=line.split(',')
        if len(fields)!=6 or fields[:3]!=['SIEVE',engine,str(limit)]:
            raise ValueError('Unexpected sieve sample: '+line[:120])
        if any(not value.isascii() or not value.isdecimal() for value in fields[3:]):
            raise ValueError('Invalid sieve sample integer')
        sample,wall,cpu=map(int,fields[3:])
        if sample!=len(rows) or wall<=0 or cpu<=0:
            raise ValueError('Unordered or nonpositive sieve sample')
        rows.append(dict(sample=sample,wall_ns=wall,cpu_ns=cpu))
    if len(rows)!=SAMPLES:
        raise ValueError('Incomplete sieve sample pass')
    return rows


def summarize(report):
    """Render only validated measurements; quality warnings preserve every raw observation."""
    if report['status']!='checks-passed':
        return 'Sieve comparison: '+report['status']+'. '+report.get('error','')+'\n'
    identities=[(item['limit'],item['engine'],item['pass_index']) for item in report['passes']]
    if len(identities)!=len(set(identities)) or set(identities)!={(limit,engine,p) for limit in LIMITS for engine in ENGINES for p in range(2)}:
        raise ValueError('Missing or duplicate sieve report pass')
    lines=['Sieve interpreter comparison (process CPU medians; all samples retained).','',
           '| Limit | Ragnarök ms | PolkaVM ms | Ratio | Quality |',
           '| --- | ---: | ---: | ---: | --- |']
    for limit in LIMITS:
        medians={};noisy=False
        for engine in ENGINES:
            # Three initial observations in each process are warmups, never mixed into the median.
            passes=[[row['cpu_ns'] for row in item['samples'][3:]] for item in report['passes']
                    if item['limit']==limit and item['engine']==engine]
            if len(passes)!=2 or any(len(values)!=10 for values in passes):
                raise ValueError('Incomplete sieve report')
            values=sorted(sum(passes,[]));centers=[statistics.median(p) for p in passes]
            medians[engine]=statistics.median(values)
            noisy|=max(centers)>1.25*min(centers) or values[17]>2*values[2]
        native,reference=(medians[e] for e in ENGINES)
        lines.append(f'| {limit} | {native/1e6:.3f} | {reference/1e6:.3f} | {native/reference:.2f}x | '+
                     ('noisy; inspect raw samples' if noisy else 'within dispersion guard')+' |')
    lines.extend(['','Execution only; preparation and complete state validation occur outside timing.',
                  'Checked release ARC/Clang ThinLTO; pinned PolkaVM Interpreter JamV1 Sync/Full/L2Hit.',
                  'These two guests do not establish general interpreter or full JAM performance.'])
    return '\n'.join(lines)+'\n'
