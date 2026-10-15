#!/usr/bin/env python3
"""Build checked ticket codecs and compare published vectors plus an independent adversarial corpus."""
import json
import subprocess
from tickets_oracle import requests
from test_support import ROOT, nim_command, reject_types
from dependencies import codec_sources


# Native selftests and independent field adapters exercise both caller-buffer APIs before reporting success.
def main():
    codec_sources()
    folder=ROOT/'build/tickets';folder.mkdir(parents=True,exist_ok=True)
    # Build sources with the same checked ARC/Clang LTO configuration as the other codec suites.
    for source,name in (('test_tickets','selftest'),('tickets_driver','driver')):
        command=nim_command(ROOT/f'tests/native/{source}.nim',folder/name,folder/f'{name}-cache')
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True)
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n')
    result=subprocess.run([str(folder/'driver'),str(path)],capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr)
    actual=result.stdout.splitlines()
    assert len(actual)==len(expected),(len(actual),len(expected))
    # Exact semantic output catches field swaps as well as byte-level round-trip defects.
    for index,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(index,lines[index][:200],got[:200],wanted[:200])
    cases=[('attempt',ROOT/'tests/native/compile_fail/raw_ticket_attempt.nim',('TicketAttempt','uint8')),
           ('proof',ROOT/'tests/native/compile_fail/swapped_ticket_proof.nim',('TicketProof','TicketAttempt'))]
    rejected=reject_types(cases,folder/'types')
    (folder/'results.json').write_text(json.dumps(dict(status='passed',requests=len(lines),nominal_rejections=len(rejected)),indent=2)+'\n')
    print(f'PASS tickets: {len(lines)} published/independent requests and {len(rejected)} nominal rejections')


# Importing the runner never builds a binary or changes upstream fixture state.
if __name__=='__main__':
    main()
