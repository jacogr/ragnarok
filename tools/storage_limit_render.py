# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Present admitted memory ceilings with availability and native control success kept explicit."""
from storage_limit_report import validate


def counts(report):
    """Count each typed trajectory, preserving unavailable and refused observations separately."""
    rows=validate(report)
    result=dict(controls=0,completed_caps=0,unavailable_caps=0,nonzero_caps=0,signal_caps=0)
    for row in rows:
        for attempt in row['attempts']:
            if attempt['cap'] is None:
                result['controls']+=1
            else:
                key={'completed':'completed_caps','unavailable':'unavailable_caps','nonzero-exit':'nonzero_caps','signal':'signal_caps'}[attempt['outcome']]
                result[key]+=1
    return result


def render(report):
    """Completed caps carry native complete-map assertions; failures retain uncertainty about cause."""
    totals=counts(report)
    lines=['# Child-local storage memory ceilings','','Host: '+report['identity']['host']['system']+'.',
           'Address-space ceilings constrain reservations, not resident memory. No paging, cold-cache or OOM attribution is established.',
           'Read-only Linux PSI/cgroup snapshots include unrelated host or group activity; unavailable is not zero.',
           'Controls: '+str(totals['controls'])+'; completed caps: '+str(totals['completed_caps'])+'; unavailable caps: '+str(totals['unavailable_caps'])+
           '; nonzero caps: '+str(totals['nonzero_caps'])+'; signalled caps: '+str(totals['signal_caps'])+'.','',
           '| Backend | Entries | Phase | Cap bytes | Outcome | Child peak RSS bytes | Minor / major faults |',
           '| --- | ---: | --- | ---: | --- | ---: | --- |']
    for row in report['rows']:
        backend,count=row['case']
        for attempt in row['attempts']:
            execution=attempt.get('execution');resources=execution['observation']['resources'] if execution else None
            peak=str(resources['peak_rss_bytes']) if resources else 'unavailable'
            faults=f'{resources["minor_faults"]} / {resources["major_faults"]}' if resources else 'unavailable'
            cap='unchanged' if attempt['cap'] is None else str(attempt['cap'])
            lines.append(f'| {backend} | {count} | {attempt["name"]} | {cap} | {attempt["outcome"]} | {peak} | {faults} |')
    lines+=['','All selected fixture bytes remain unchanged. Both unrestricted controls validate the exact producer root and complete authored map.',
            'Exec launcher startup is included in child resources. Producer construction and parent fingerprinting are excluded; either may warm the OS cache.',
            'A signal or nonzero native exit is an observation, not a validated reopen or proof of allocation refusal. Hardware power-loss qualification remains separate.']
    return '\n'.join(lines)+'\n'
