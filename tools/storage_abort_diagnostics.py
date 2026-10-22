#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Capture Linux abort call chains separately from the unchanged memory-ceiling measurement binary.

Make owns setup. The ordinary panel runs first; a symbolized checked ARC/Clang LTO comparison
then uses the same closed fixtures, child-only cap, strict controls and byte-preservation checks.
LLDB stays uncapped and follows the existing Python launcher's exec into the native executable.
"""
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import sys
import tempfile

from build_crypto import build_native, dependencies
from native_checks import NativeChecks
from pvm_reference import command
from setup_nimony import installed
from storage_benchmark import atomic_text
from storage_fresh_reopen import parse_prepared, parse_reopened
from storage_limit_child import EXEC
from storage_limit_namespace import fingerprint
from storage_limit_provenance import ROOT, SOURCE, identity
from storage_limit_receipts import validate_limit
from storage_limit_supervision import execute
from storage_memory_ceilings import run as ceilings

BUILD = ROOT/'build/tests/storage-abort-diagnostics'
CAP = 128*1024*1024
COUNT = 131072


def debugger_command(debugger, binary, receipt, backend, owned, root):
    """Keep debugger memory outside the cap; the existing launcher caps only its exec descendant."""
    return [debugger, '--batch',
            '-o', 'settings set target.disable-aslr false',
            '-o', 'settings set target.process.stop-on-exec false',
            '-o', 'process handle SIGABRT --stop true --notify true --pass true',
            '-o', 'run', '-k', 'thread backtrace --count 64', '-k', 'continue',
            '--', sys.executable, str(EXEC), str(receipt), str(CAP), '--',
            str(binary), 'open', backend, str(COUNT), str(owned), root]


def validate_trace(raw):
    """Require an actual SIGABRT stop, native frames and fatal continuation, never debugger exit alone.

    A captured stack is evidence for manual call-site diagnosis, not an automatic OOM classification.
    Symbolized and ordinary executions remain separate because adding DWARF can affect layout.
    """
    trace = raw.split('(lldb) thread backtrace --count 64', 1)[-1].split('(lldb) continue', 1)[0]
    frames = re.findall(r'^\s*\*?\s*frame #\d+:.*$', trace, re.MULTILINE)
    if ('stop reason = signal SIGABRT' not in raw or len(frames) < 2 or
            not any(re.search(r'(?:limits|symbols)-native`', frame) for frame in frames) or
            re.search(r'Process [0-9]+ exited with status = 6 \(0x00000006\)', raw) is None):
        raise ValueError('Missing native SIGABRT stop/backtrace/fatal continuation')
    return frames


def run(folder=BUILD):
    """Retain raw failures and publish success only after both backends preserve bytes and controls pass."""
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    for name in ('results.json', 'summary.md'):
        # Old successful summaries cannot survive an unsupported host, missing debugger or failed run.
        (folder/name).unlink(missing_ok=True)
    report = dict(status='running', schema_version=1, checks=[], rows=[])

    def save():
        """Atomic receipts preserve completed stages when compilation, ptrace or the workload fails."""
        atomic_text(folder/'results.json', json.dumps(report, indent=2)+'\n')

    save()
    try:
        if platform.system() != 'Linux':
            raise RuntimeError('Abort call-site qualification requires Linux')
        debugger = shutil.which('lldb')
        if debugger is None:
            raise RuntimeError('Install the Linux LLDB host tool before this diagnostic')
        version = command([debugger, '--version'], 'debugger-version', folder, timeout=30)
        report['checks'].append(version)
        if version['exit_code'] != 0:
            raise RuntimeError('LLDB version check failed')
        report['debugger_version'] = Path(version['log']).read_text()
        # The original optimized profile remains the measurement/control binary; it gets no hooks.
        panel = ceilings(folder/'ordinary')
        report['ordinary_identity'] = panel['identity']
        report['ordinary_report'] = str(folder/'ordinary/results.json')
        report['ordinary_sha256'] = hashlib.sha256(Path(report['ordinary_report']).read_bytes()).hexdigest()
        if any(probe['observed']['status'] != 'enforced' for probe in panel['probes']):
            raise RuntimeError('Linux did not establish every ordinary child-memory ceiling')
        compiler, _ = installed()
        library = build_native(dependencies(False))
        build, binary = NativeChecks(folder).build(compiler, SOURCE, 'symbols-native',
                                                   crypto_library=library, cflags=('-g',))
        build.pop('output', None)
        report['checks'].append(build)
        save()
        if build['exit_code'] != 0:
            raise RuntimeError('Symbolized checked build failed: '+build['log'])
        report['symbolized_identity'] = identity(compiler, library, binary)
        for backend in ('journal', 'managed'):
            ordinary = next(row for row in panel['rows'] if row['case'] == [backend, COUNT])
            capped = next(attempt for attempt in ordinary['attempts'] if attempt['cap'] == CAP)
            if (capped['outcome'] != 'signal' or
                    capped['execution']['observation']['exit_code'] != -6):
                raise RuntimeError('Ordinary profile did not reproduce the expected native SIGABRT')
            with tempfile.TemporaryDirectory(prefix=backend+'-', dir=folder) as owned:
                # A separately closed producer supplies the exact root; no graph enters the consumer.
                prepared = command([binary, 'prepare', backend, COUNT, owned],
                                   'prepare-'+backend, folder, timeout=300)
                report['checks'].append(prepared)
                if prepared['exit_code'] != 0:
                    raise RuntimeError('Symbolized producer failed: '+prepared['log'])
                raw = Path(prepared['log']).read_text()
                root = parse_prepared(raw, backend, COUNT)
                before = fingerprint(Path(owned)/'store', backend)
                row = dict(backend=backend, count=COUNT, owned=owned, root=root,
                           prepared_raw=raw, selected_before=before, controls=[], traces=[])
                report['rows'].append(row)
                for phase in ('before', 'ordinary-abort', 'symbolized-abort', 'after'):
                    # Strict unrestricted controls bracket the debugger attempt on its same namespace.
                    if phase in ('before', 'after'):
                        args = [str(binary), 'open', backend, str(COUNT), owned, root]
                        control = execute(args, None, owned, folder, backend+'-'+phase)
                        if control['outcome'] != 'completed':
                            raise RuntimeError('Symbolized unrestricted control failed')
                        control['native'] = parse_reopened(control['raw'], backend, COUNT, root)
                        row['controls'].append(control)
                    else:
                        receipt = Path(owned)/(phase+'-limit.json')
                        target = Path(folder/'ordinary/limits-native') if phase == 'ordinary-abort' else binary
                        argv = debugger_command(debugger, target, receipt, backend, owned, root)
                        traced = command(argv, backend+'-'+phase, folder, timeout=300)
                        report['checks'].append(traced)
                        trace = dict(kind=phase, binary=str(target), raw=Path(traced['log']).read_text())
                        row['traces'].append(trace)
                        # LLDB's exit is distinct from the inferior's actual SIGABRT continuation.
                        if traced['exit_code'] != 0:
                            raise RuntimeError('Debugger failed: '+traced['log'])
                        trace['frames'] = validate_trace(trace['raw'])
                        trace['limit_raw'] = receipt.read_text()
                        trace['limit'] = validate_limit(json.loads(trace['limit_raw']), CAP)
                        if trace['limit']['status'] != 'applied':
                            raise RuntimeError('Debugger descendant did not apply the requested cap')
                    after = fingerprint(Path(owned)/'store', backend)
                    if before != after:
                        raise ValueError('Abort diagnostic changed selected bytes')
                    row['selected_after'] = after
                    save()
        if identity(compiler, library, binary) != report['symbolized_identity']:
            raise RuntimeError('Abort diagnostic inputs changed')
        report['status'] = 'traces-captured'
        save()
        lines = ['# Linux storage abort diagnostics', '',
                 'Ordinary checked memory-ceiling panel passed separately. Symbolized comparison',
                 'retains ARC, Clang LTO and bounds checks; only C debug information is added.',
                 'The debugger is uncapped. Native descendants read back the 128 MiB soft ceiling.',
                 'Both backends passed strict before/after controls and preserved selected bytes.',
                 'Call chains require source inspection; SIGABRT alone is not an OOM diagnosis.', '']
        for row in report['rows']:
            # Raw logs remain authoritative; bounded frames make the allocating caller reviewable.
            for trace in row['traces']:
                lines += ['## '+row['backend']+' '+trace['kind'], '',
                          '```text', *trace['frames'], '```', '']
        atomic_text(folder/'summary.md', '\n'.join(lines)+'\n')
        print('PASS Linux abort traces and preserved-byte controls: '+str(folder/'results.json'))
        return report
    except Exception as error:
        report.update(status='failed', error=str(error))
        (folder/'summary.md').unlink(missing_ok=True)
        save()
        raise


# Importing parsers never starts LLDB, applies limits or constructs storage fixtures.
if __name__ == '__main__':
    run()
