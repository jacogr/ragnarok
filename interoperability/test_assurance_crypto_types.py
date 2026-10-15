#!/usr/bin/env python3
"""Six intentional parent/anchor and transcript/signature domain rejection probes."""
import json
import subprocess
from assurance_crypto_oracle import ROOT
from mojo_support import compiler


# Require the intended wrong-domain diagnostic, not merely an unrelated nonzero compiler exit.
def main():
    folder=ROOT/'build/assurance-crypto/types';folder.mkdir(parents=True,exist_ok=True)
    values=[]
    # Each candidate receives independently compiled nominal parent and signing-message violations.
    for language in ('nim','odin','mojo'):
        # Separate sources prevent the first error from concealing an accidentally accepted second misuse.
        for case in ('parent','message'):
            source=ROOT/f'{language}/tests/compile_fail/assurance_context_{case}.{language if language!="odin" else "odin"}'
            # Prefer semantic-only checking when the language exposes it publicly.
            if language=='nim':
                command=['nim','check','--skipParentCfg','--skipUserCfg',str(source)]
                names=('AssuranceParent','AssuranceAnchor') if case=='parent' else ('EdSignature','AssuranceSigningMessage')
            elif language=='odin':
                # Single-file mode isolates intentional invalid fixtures from ordinary package tests.
                command=['odin','check',str(source),'-file']
                names=('Assurance_Parent','Assurance_Anchor') if case=='parent' else ('Ed_Signature','Assurance_Signing_Message')
            else:
                # Mojo rejects before linking this disposable target; no crypto provider is needed.
                command=[compiler(),'build','-I',str(ROOT/'mojo'),str(source),'-o',str(folder/f'rejected-{case}')]
                names=('AssuranceParent','AssuranceBytes') if case=='parent' else ('PublicBytes','AssuranceSigningMessage')
            result=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=90)
            output=result.stdout+result.stderr
            path=folder/f'{language}-{case}.log';path.write_text(output)
            assert result.returncode!=0,(language,case,'wrong nominal domain accepted')
            assert 'error' in output.lower() and all(name in output for name in names),(language,case,output)
            values.append(dict(language=language,case=case,intentional=True,command=command,
                               returncode=result.returncode,log=str(path.relative_to(ROOT))))
    (folder/'results.json').write_text(json.dumps(values,indent=2)+'\n')
    print('PASS 6 assurance context nominal-domain rejection probes')


# Importing this module must not execute deliberate compiler failures implicitly.
if __name__=='__main__':
    main()
