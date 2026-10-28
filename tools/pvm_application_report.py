# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Render lifecycle and coverage evidence from an already checked native application cohort.

Formatting never launches execution or pools samples across processes. Every cell keeps its
forward/reverse order; core reset/publication and reference restore/teardown retain distinct scopes.
"""
import statistics


def lifecycle_sections(report):
    """Supplement reused call medians with owned preparation, cold calls, reset/publication and native coverage."""
    rows = {(r['case'],r['limit'],r['order'],r['role']):r['parsed'] for r in report['runs']}
    if len(rows) != len(report['runs']):
        raise ValueError('Duplicate application process identity')
    cases = [(r['case'],r['limit']) for r in report['runs'] if r['order']==0 and r['role']=='jit']
    if len(cases) != len(set(cases)):
        raise ValueError('Duplicate application case identity')

    def paired(case, limit, role, value, milliseconds=True):
        """Render each process independently; constructor/cold values are never substituted for reused medians."""
        result = []
        for order in (0,1):
            number = value(rows[case,limit,order,role])
            result.append(f'{number/1e6:.3f}' if milliseconds else f'{number:,}')
        return ' / '.join(result)

    def median(parsed, key):
        """Ordinary reused measurements retain exactly samples three through twelve."""
        samples = parsed['execution']['samples']
        if len(samples) != 13:
            raise ValueError('Incomplete lifecycle process')
        return statistics.median(x[key] for x in samples[3:])

    def table(title, columns):
        """Keep one flat scope per table; each numeric cell uses the same explicit forward/reverse convention."""
        output = ['',title,'','| Case | '+' | '.join(name for name,_,_,_ in columns)+' |',
                  '|---|'+'---:|'*len(columns)]
        for case,limit in cases:
            values = [paired(case,limit,role,value,ms) for _,role,value,ms in columns]
            output.append('| '+case+' '+str(limit)+' | '+' | '.join(values)+' |')
        return output

    lines = ['','All following CPU values are milliseconds, forward / reverse. Constructors and cold calls are separate from reused calls.']
    lines += table('Public owner construction and cold sample zero',[
        ('Interpreter owner','interpreter',lambda p:p['execution']['preparation_ns'][0],True),
        ('Previous owner','baseline',lambda p:p['execution']['preparation_ns'][0],True),
        ('Current owner','jit',lambda p:p['execution']['preparation_ns'][0],True),
        ('Interpreter cold','interpreter',lambda p:p['execution']['samples'][0]['cpu_ns'],True),
        ('Previous cold','baseline',lambda p:p['execution']['samples'][0]['cpu_ns'],True),
        ('Current cold','jit',lambda p:p['execution']['samples'][0]['cpu_ns'],True),
        ('Reference cold call','reference',lambda p:p['execution']['samples'][0]['cpu_ns'],True)])
    lines += table('Retained core construction and reused lifecycle; these are not public-call ratios',[
        ('Facts constructor','core',lambda p:p['execution']['preparation_ns'][0],True),
        ('Memory/frame constructor','core',lambda p:p['execution']['preparation_ns'][1],True),
        ('Reused reset','core',lambda p:median(p,'reset_ns'),True),
        ('Reused call','core',lambda p:median(p,'cpu_ns'),True),
        ('Reused publication','core',lambda p:median(p,'publication_ns'),True),
        ('Reused total','core',lambda p:median(p,'lifecycle_ns'),True)])
    lines += ['','Reference DOOM invocation lifecycle; module construction remains separate','',
              '| Case | Restore | Call | Teardown | Total |','|---|---:|---:|---:|---:|']
    for case,limit in cases:
        if case in ('init','tick'):
            # Independent component medians need not sum to the median of complete invocation totals.
            values = [paired(case,limit,'reference',lambda p,key=key:statistics.median(
                x[key] for x in p['execution']['lifecycle'][3:]))
                for key in ('restore_ns','cpu_ns','teardown_ns','lifecycle_ns')]
            lines.append('| '+case+' | '+' | '.join(values)+' |')
    lines += table('Current public native totals across all thirteen calls; source attempts are per retained-core call, not hardware instructions',[
        ('Publications','jit',lambda p:p['native']['fragments'],False),
        ('Native calls','jit',lambda p:p['native']['calls'],False),
        ('Lowered operations','jit',lambda p:p['native']['operations'],False),
        ('Code used bytes','jit',lambda p:p['native']['code_bytes'],False),
        ('Conditional calls','jit',lambda p:p['native']['branches'],False),
        ('Whole-header calls','jit',lambda p:p['native']['headers'],False),
        ('Compilation CPU','jit',lambda p:p['native']['compilation_ns'],True),
        ('Source attempts/call','core',lambda p:p['execution']['samples'][3]['attempts'],False)])
    return '\n'.join(lines)+'\n'
