#!/usr/bin/env python3
"""Deliberate nominal-domain rejection probes; these are diagnostics, never repair iterations."""
import json
import subprocess
from assurances_oracle import ROOT
from mojo_support import compiler


# Verify that each compiler rejects the intended type boundary, rather than a missing import/tool.
def main():
    folder = ROOT / 'build/assurances/types'
    folder.mkdir(parents=True, exist_ok=True)
    records = []
    # Each case tests a separate boundary, so early termination cannot hide another accepted misuse.
    for language in ('nim', 'odin', 'mojo'):
        # Anchor/signature, index/count and core/validator domains must remain distinct in every language.
        for case in ('anchor', 'index', 'config'):
            suffix = {'nim':'nim', 'odin':'odin', 'mojo':'mojo'}[language]
            source = ROOT / f'{language}/tests/compile_fail/assurances_{case}.{suffix}'
            # Use the public compiler's semantic checker where available; Mojo builds a disposable target.
            if language == 'nim':
                command = ['nim', 'check', '--skipParentCfg', '--skipUserCfg', str(source)]
                names = {'anchor':('AssuranceAnchor','AssuranceSignature'),
                         'index':('ValidatorIndex','CoreCount'),
                         'config':('CoreCount','ValidatorCount')}[case]
            elif language == 'odin':
                # Single-file mode keeps deliberately invalid fixtures outside ordinary test packages.
                command = ['odin', 'check', str(source), '-file']
                names = {'anchor':('Assurance_Anchor','Assurance_Signature'),
                         'index':('Validator_Index','Core_Count'),
                         'config':('Core_Count','Validator_Count')}[case]
            else:
                # The pinned SDK exposes build, which must reject before emitting an executable.
                command = [compiler(), 'build', '-I', str(ROOT/'mojo'), str(source),
                           '-o', str(folder/f'rejected-{case}')]
                names = {'anchor':('AssuranceBytes','64','32'),
                         'index':('ValidatorIndex','Quantity'),
                         'config':('Quantity','9','10')}[case]
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=90)
            output = result.stdout + result.stderr
            path = folder / f'{language}-{case}.log'
            path.write_text(output)
            assert result.returncode != 0, (language, case, 'invalid domain accepted')
            assert 'error' in output.lower() and all(name in output for name in names), (language, case, output)
            records.append(dict(language=language, case=case, intentional=True,
                                command=command, returncode=result.returncode,
                                log=str(path.relative_to(ROOT))))
    (folder/'results.json').write_text(json.dumps(records, indent=2)+'\n')
    print('PASS 9 assurances nominal-domain compiler rejection probes')


# Importing this helper must not invoke any compiler.
if __name__ == '__main__':
    main()
