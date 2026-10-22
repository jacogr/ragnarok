# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run and atomically publish fully validated bounded storage memory-ceiling experiments."""
import json
from pathlib import Path
from storage_benchmark import atomic_text
from storage_limit_collect import collect
from storage_limit_report import validate
from storage_limit_provenance import ROOT

BUILD=ROOT/'build/tests/storage-memory-ceilings'


def run(folder=BUILD):
    """Retire public artifacts before work; failures retain diagnostics without stale success."""
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    for name in ('results.json','summary.md','observations.csv'):
        (folder/name).unlink(missing_ok=True)
    report=None
    try:
        report=collect(folder);report['status']='checks-passed';validate(report)
        atomic_text(folder/'results.json',json.dumps(report,indent=2)+'\n')
        print('PASS native controls and memory ceiling evidence: '+str(folder/'results.json'))
        return report
    except Exception as error:
        if report is None:
            try:
                report=json.loads((folder/'results.json').read_text())
            except (OSError,ValueError):
                report={}
        report.update(status='failed',error=str(error))
        for name in ('summary.md','observations.csv'):
            (folder/name).unlink(missing_ok=True)
        atomic_text(folder/'results.json',json.dumps(report,indent=2)+'\n');raise


# Make owns setup; importing the panel never builds or starts memory experiments.
if __name__=='__main__':
    run()
