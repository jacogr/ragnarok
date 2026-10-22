# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Setup-free memory-ceiling summary retains unsupported caps and fails missing or malformed evidence."""
import argparse
import json
from pathlib import Path
from storage_benchmark import atomic_text
from storage_limit_render import counts


def summarize(path):
    """Passing unrestricted controls cannot silently imply Linux enforcement on an unsupported host."""
    try:
        report=json.loads(Path(path).read_text());value=counts(report)
    except (OSError,ValueError,KeyError,TypeError) as error:
        reason=str(error).replace('|','/').replace('\n',' ')[:180]
        return '## Child-local storage memory ceilings\n\nEvidence unavailable or invalid: '+reason+'\n',True
    lines=['## Child-local storage memory ceilings','','Host: '+report['identity']['host']['system']+'.',
           'Address-space bounds are distinct from paging, resident-memory limits and OOM attribution.','',
           '| Native controls | Completed caps | Unavailable caps | Nonzero caps | Signalled caps |',
           '| ---: | ---: | ---: | ---: | ---: |',
           '| '+ ' | '.join(str(value[k]) for k in ('controls','completed_caps','unavailable_caps','nonzero_caps','signal_caps'))+' |']
    return '\n'.join(lines)+'\n',False


def main():
    """Append to the existing job summary while retaining a separate source-owned artifact."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report',type=Path,default=Path(__file__).resolve().parents[1]/'build/tests/storage-memory-ceilings/results.json')
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--artifact',type=Path,default=Path(__file__).resolve().parents[1]/'build/tests/storage-memory-ceilings/status.md')
    args=parser.parse_args();text,failed=summarize(args.report)
    args.artifact.parent.mkdir(parents=True,exist_ok=True);atomic_text(args.artifact,text)
    with args.output.open('a') as stream:
        stream.write('\n'+text)
    raise SystemExit(1 if failed else 0)


# Summary inspection never provisions tools or launches child experiments.
if __name__=='__main__':
    main()
