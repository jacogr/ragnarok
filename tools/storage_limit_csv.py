# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Export validated child memory trajectories without converting unavailable resources into zeros."""
import csv
import io
from storage_limit_report import validate


def export(report):
    """Each fixed case/phase carries actual exit/resources or explicit unavailable cells."""
    rows=validate(report);output=io.StringIO();writer=csv.writer(output,lineterminator='\n')
    writer.writerow(('backend','entries','phase','cap_bytes','outcome','exit_code','peak_rss_bytes','minor_faults','major_faults','native_checks'))
    for row in rows:
        backend,count=row['case']
        for attempt in row['attempts']:
            execution=attempt.get('execution');observation=execution['observation'] if execution else None
            resources=observation['resources'] if observation else {}
            writer.writerow((backend,count,attempt['name'],'unchanged' if attempt['cap'] is None else attempt['cap'],attempt['outcome'],
                             observation['exit_code'] if observation else 'unavailable',
                             *[resources.get(k,'unavailable') for k in ('peak_rss_bytes','minor_faults','major_faults')],
                             attempt.get('native',{}).get('checks','unavailable')))
    return output.getvalue()
