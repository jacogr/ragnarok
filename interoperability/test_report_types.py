#!/usr/bin/env python3
"""Reproduce the complete-report nominal hash safeguards; expected failures are diagnostics."""
import hashlib
import json
import subprocess
from pathlib import Path
from mojo_support import compiler
from report_oracle import ROOT


# Require intended type/domain rejection, not a missing compiler, import failure or unrelated nonzero exit.
def main():
    folder = ROOT/'build/report'
    folder.mkdir(parents=True,exist_ok=True)
    commands = {
        'nim':['nim','check','--mm:arc',ROOT/'nim/tests/compile_fail/swapped_report_root.nim'],
        'odin':['odin','check',ROOT/'odin/tests/compile_fail/swapped_report_root.odin','-file'],
        'mojo':[compiler(),'build','-I',ROOT/'mojo',ROOT/'mojo/tests/compile_fail/swapped_report_root.mojo','-o',folder/'wrong-report-root'],
    }
    records = []
    for language,command in commands.items():
        # Each direct intentional compiler probe gets its actual command, diagnostic and fixture hash.
        command = list(map(str,command))
        result = subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=60)
        text = result.stdout+result.stderr
        log = folder/f'{language}-report-types.log';log.write_text(text)
        assert result.returncode != 0 and any(marker in text for marker in ('type mismatch','Cannot assign value','cannot implicitly convert')), (language,text)
        assert 'SegmentRoot' in text or 'Segment_Root' in text or 'ReportHash' in text, (language,text)
        assert 'PackageHash' in text or 'Package_Hash' in text, (language,text)
        fixture = next(Path(part) for part in command if 'swapped_report_root.' in part)
        records.append(dict(language=language,role='intentional diagnostic, not a compiler repair',command=command,
                            returncode=result.returncode,fixture_sha256=hashlib.sha256(fixture.read_bytes()).hexdigest(),
                            log=str(log.relative_to(ROOT)),log_sha256=hashlib.sha256(log.read_bytes()).hexdigest()))
        print(f'PASS {language}: compiler rejects a segment root assigned to a package hash',flush=True)
    (folder/'type-checks.json').write_text(json.dumps(records,indent=2)+'\n')


# Importing diagnostic metadata must not invoke compilers.
if __name__ == '__main__':
    main()
