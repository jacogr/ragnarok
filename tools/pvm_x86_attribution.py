#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Collect bounded public-call work diagnostics through the canonical performance controller.

Only Linux x86 manual CI may execute this adapter. Normal and request/debug images are
separate; both runtime policies share each image. Counts never publish timing/latest evidence.
"""
import io
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile
import tempfile

from native_checks import ROOT
from pvm_ci_performance import PerformanceRunner, command_record, digest, execution_environment
from pvm_guest_compare import snapshot_imports, unchanged
from pvm_instruction_profile import (calibrate_scope, capture_generated_sources, collect,
                                     exclusive_costs, final_return_dump, profile_counts)
from pvm_native_ci import host_identity
from pvm_x86_jit_profile import matching_native_activity, selected_symbol
from setup_nimony import cache_directory

SCHEMA = 'pvm-x86-attribution-v1'
VERSION = 'valgrind-3.26.0'
EVENTS = ('Ir', 'Bc', 'Bcm', 'Bi', 'Bim')
NATIVE_FIELDS = ('fragments', 'calls', 'operations', 'code_bytes', 'branches', 'headers')
CASE = dict(case_id='sieve-1000', case='sieve', limit=1000, family='guest')
SHARED_FILES = ('spec/toolchain.json', 'spec/pins.json', 'spec/polkavm-pins.json',
                'spec/bandersnatch-pins.json', 'tests/performance/pvm_sieve.nim',
                'tests/performance/pvm_profile_scope.h')
# These immutable completed packets were independently reviewed before this diagnostic was authorized.
# The parent runtime is a squash of its original qualification; preserve both identities explicitly.
PROVENANCE = dict(
    parent=dict(runtime='e2858bf5bc0cf34fd82a71ffd91b35336f8399c1',
        revision='74696c7cb76bcf23849a91c9db45b5eb85156a1b', run='42032705266',
        native='5922c3b08df564c68b6588c9c556a9a2faad4e00ba462a43c33073383fb21330',
        performance='655224a1947df0a851198ba7269962e7f39de3df89f9d81d87e0e000c3b1d285'),
    candidate=dict(runtime='52e72e4b7a9ebf8ec6f8ff40cee9e4d995d22d65',
        revision='52e72e4b7a9ebf8ec6f8ff40cee9e4d995d22d65', run='42042845187',
        native='c0e247654eb4eac8358ffcf4014ca9646e6d77a4259d94e18343c2492df9f861',
        performance='c540ee6a4c50d3f3c1a32ce84e4aa6b80ba06d1d3c260625ada643c37e99bb52'))


def historical_binding(native_path, performance_path, expected, sources, shared, compiler, clang):
    """Bind actual completed receipts to exact runtime bytes without relabeling historical Git revisions."""
    if digest(native_path) != expected['native'] or digest(performance_path) != expected['performance']:
        raise ValueError('Historical native/performance receipt digest mismatch')
    native, performance = json.loads(native_path.read_text()), json.loads(performance_path.read_text())
    identity = performance['identity']
    all_opcodes = [row for row in native['qualification'] if row['name'] == 'all-opcodes']
    if (native['status'] != 'passed' or performance['status'] != 'passed'
            or performance['schema'] != 'pvm-performance-v2'
            or native['revision'] != expected['revision'] or performance['revision'] != expected['revision']
            or identity['ci']['GITHUB_RUN_ID'] != expected['run']
            or identity['ci']['GITHUB_SHA'] != expected['revision']
            or identity['native_qualification']['sha256'] != expected['native']
            or identity['native_qualification']['revision'] != expected['revision']
            or native['host']['architecture'] != 'x86_64'
            or identity['host'] != native['host']
            or native['compiler_sha256'] != compiler or identity['compiler']['sha256'] != compiler
            or identity['clang'] != clang
            or native['policies']['native_build_defines'] != ['pvmX86Jit']
            or native['policies']['native_jit_available'] is not True
            or len(all_opcodes) != 1 or any(all_opcodes[0][kind]['exit_code'] != 0
                                         for kind in ('build', 'run'))):
        raise ValueError('Missing completed, source-bound historical native qualification')
    files = identity['files']
    anchors = [name for name in files if name.endswith('/build/tests/pvm-native/results.json')]
    if len(anchors) != 1:
        raise ValueError('Ambiguous historical checkout source root')
    prefix = anchors[0].removesuffix('build/tests/pvm-native/results.json')
    relative = {name[len(prefix):]: value for name, value in files.items() if name.startswith(prefix)}
    runtime = {name: value for name, value in relative.items()
               if name.startswith(('src/', 'native/pvm_jit/'))}
    if runtime != sources or any(relative.get(name) != value for name, value in shared.items()):
        raise ValueError('Historical runtime/header/driver/pin bytes differ from exact runtime')
    qualified = {name: value for name, value in native['sources'].items()
                 if name.startswith(('src/', 'native/pvm_jit/'))}
    if (not qualified or any(sources.get(name) != value for name, value in qualified.items())
            or {name for name in qualified if name.endswith('.nim')} !=
               {name for name in sources if name.endswith('.nim')}):
        raise ValueError('Historical native source coverage differs from archived runtime')
    return dict(runtime_revision=expected['runtime'], qualification_revision=expected['revision'],
                original_run=expected['run'], native_sha256=expected['native'],
                performance_sha256=expected['performance'], matched_runtime_files=len(sources),
                full_golden_exit_code=all_opcodes[0]['run']['exit_code']), performance


def unsigned(value, position=False):
    """Decode only bounded absolute positions/counters; compressed positions are not this mode's format."""
    pattern = r'(?:0|[1-9][0-9]*|0x[0-9a-fA-F]+)' if position else r'(?:0|[1-9][0-9]*)'
    if re.fullmatch(pattern, value) is None:
        raise ValueError('Invalid absolute Callgrind position or counter')
    number = int(value, 16 if value.startswith('0x') else 10)
    if number >= 1 << 64:
        raise ValueError('Callgrind position or counter exceeds uint64')
    return number


def positioned_costs(text, instructions=False):
    """Validate every self/arc row and conserve all events without counting inclusive arcs as self work.

    Collection explicitly disables position/string compression. The documented association is
    calls=count,target-position followed immediately by a source-position/inclusive-cost row.
    See https://valgrind.org/docs/manual/cl-format.html; anonymous native code stays anonymous.
    """
    totals = profile_counts(text)
    positions = ['instr', 'line'] if instructions else ['line']
    if (tuple(totals) != EVENTS or any(value >= 1 << 64 for value in totals.values())
            or re.findall(r'^positions: (.+)$', text, re.M) != [' '.join(positions)]):
        raise ValueError('Unsupported attribution events or positions')
    context = dict(ob='???', fl='???', fn='')
    destination = {}
    callee, pending = '', None
    own, arcs, rows = {}, [], []
    for line in text.splitlines():
        # Header/footer and blank/comment records carry no executable cost.
        if not line or line.startswith('#'):
            continue
        if re.match(r'^(?:version|creator|pid|cmd|part|thread|desc|event|events|positions|summary|totals):', line):
            if pending is not None:
                raise ValueError('Incomplete Callgrind call arc before header/footer')
            continue
        if '=' in line:
            key, value = line.split('=', 1)
            if pending is not None:
                raise ValueError('Incomplete Callgrind call arc')
            if key == 'calls':
                fields = value.split()
                if not context['fn'] or not callee or len(fields) != len(positions)+1:
                    raise ValueError('Call arc lacks caller, callee or target positions')
                pending = dict(callee=callee, callee_object=destination.get('object', context['ob']),
                               callee_file=destination.get('file', context['fl']), calls=unsigned(fields[0]),
                               target=[unsigned(item, True) for item in fields[1:]])
            elif key in ('ob', 'fl', 'fi', 'fe', 'fn', 'cob', 'cfl', 'cfi', 'cfn'):
                if not value or value.startswith('('):
                    raise ValueError('Missing or compressed Callgrind name')
                if key == 'fn':
                    # Target specifications persist until explicitly rebound, including across caller functions.
                    context['fn'] = value
                elif key == 'cfn':
                    callee = value
                elif key in ('cob', 'cfl', 'cfi'):
                    destination['object' if key == 'cob' else 'file'] = value
                elif key in ('ob', 'fl', 'fi', 'fe'):
                    context['fl' if key in ('fi', 'fe') else key] = value
            else:
                raise ValueError('Unsupported Callgrind association: '+key)
            continue
        fields = line.split()
        if not context['fn'] or not len(positions) < len(fields) <= len(positions)+len(EVENTS):
            raise ValueError('Callgrind cost row lacks function, positions or events')
        point = [unsigned(value, True) for value in fields[:len(positions)]]
        values = [unsigned(value) for value in fields[len(positions):]]
        costs = dict(zip(EVENTS, values+[0]*(len(EVENTS)-len(values))))
        row = dict(object=context['ob'], file=context['fl'], function=context['fn'],
                   position=point, events=costs)
        if pending is not None:
            # Even zero-call synthetic ancestry has inclusive costs and must never inflate self totals.
            arcs.append(dict(row, **pending))
            pending = None
        else:
            rows.append(row)
            counted = own.setdefault(context['fn'], dict.fromkeys(EVENTS, 0))
            for event in EVENTS:
                counted[event] += costs[event]
    if pending is not None or any(sum(row[event] for row in own.values()) != totals[event]
                                  for event in EVENTS):
        raise ValueError('Incomplete arc or nonconserving exclusive attribution costs')
    if not instructions and own != exclusive_costs(text):
        raise ValueError('Independent line self-cost parsers disagree')
    return dict(counts=totals, self_costs=own, arcs=arcs, positions=rows)


def native_evidence(parsed, role):
    """Retain six real counters, rejecting fallback/empty JIT activity and discarding all clock fields."""
    native = parsed['native']
    values = {key: native[key] for key in NATIVE_FIELDS}
    if (role not in ('interpreted', 'jit') or len(parsed['execution']['samples']) != 13
            or any(type(value) is not int or value < 0 for value in values.values())
            or (role == 'interpreted' and any(values.values()))
            or (role == 'jit' and not all(values.values()))):
        raise ValueError('Incomplete calls or incorrect native execution policy')
    return values


def read_parts(final, instructions=False, reference=None):
    """Audit every invocation identity/event/arc/position, including warmups and cross-pass agreement."""
    final = Path(final)
    base = Path(str(final).removesuffix('.13'))
    if base == final or final_return_dump(base, 13) != final:
        raise ValueError('Missing final invocation dump')
    final_counts = profile_counts(base.read_text(), allow_empty=True)
    if tuple(final_counts) != EVENTS or any(final_counts.values()):
        raise ValueError('Costs remain after final invocation')
    result, process = [], None
    for index in range(1, 14):
        text = Path(str(base)+'.'+str(index)).read_text()
        parts = re.findall(r'^part: ([1-9][0-9]*)$', text, re.M)
        pids = re.findall(r'^pid: ([1-9][0-9]*)$', text, re.M)
        if parts != [str(index)] or len(pids) != 1 or (process is not None and pids[0] != process):
            raise ValueError('Profile invocation parts have mixed or missing identities')
        process = pids[0]
        parsed = positioned_costs(text, instructions)
        if reference is not None and parsed['counts'] != reference[index-1]['counts']:
            raise ValueError('Line/machine invocation events disagree')
        result.append(parsed)
    return result


class AttributionRunner(PerformanceRunner):
    """Own one bounded non-timing collection and the separate immutable runtime/build identities."""

    def __init__(self, folder, parent, candidate, expected_revision=None, scope='micro'):
        """Reject mutable/option-like refs and wider scopes before any tool or guest is reachable."""
        if (scope != 'micro' or any(type(value) is not str or
                re.fullmatch(r'[0-9a-f]{40}', value) is None for value in (parent, candidate))
                or parent != PROVENANCE['parent']['runtime']
                or candidate != PROVENANCE['candidate']['runtime']):
            raise ValueError('Attribution requires micro scope and two distinct exact runtime SHAs')
        super().__init__(folder, scope, expected_revision)
        self.cases = [dict(CASE)]
        self.runtimes = dict(parent=parent, candidate=candidate)
        self.transient = {}
        self.historical = {}
        self.report.update(schema=SCHEMA, scope='x86-attribution-sieve1000',
            clock_policy='discarded', hardware_counters=False, profiles=[], normal_controls=[],
            runtime_revisions=self.runtimes, runtime_sources={}, diagnostic_builds=[])

    def verify(self):
        """Protect both permanent evidence and the currently active private source snapshot."""
        super().verify()
        unchanged(self.transient)

    def git(self, *arguments):
        """Pass already validated source selectors as separate Git arguments, never shell text."""
        self.verify()
        data = subprocess.check_output(['git', *arguments], cwd=ROOT)
        self.verify()
        return data

    def stage_inputs(self):
        """Reuse sealed local receipts or download each exact original artifact once, with no retry."""
        for role, expected in PROVENANCE.items():
            target = self.folder/'historical'/role
            paths = [target/(name+'.json') for name in ('native', 'performance')]
            if any(path.exists() for path in paths) and not all(path.is_file() for path in paths):
                raise ValueError('Incomplete staged historical receipt pair: '+role)
            if not any(path.exists() for path in paths):
                target.mkdir(parents=True, exist_ok=True)
                state = json.loads(self.command(['gh', 'run', 'view', expected['run'], '--repo',
                    'jacogr/ragnarok', '--json', 'status,conclusion,headSha'], role+'-historical-run')['output'])
                if (state.get('status') != 'completed' or state.get('conclusion') != 'success'
                        or state.get('headSha') != expected['revision']):
                    raise ValueError('Historical qualification run did not complete successfully')
                with tempfile.TemporaryDirectory(prefix='history-', dir=self.folder) as temporary:
                    self.command(['gh', 'run', 'download', expected['run'], '--repo', 'jacogr/ragnarok',
                        '--name', 'pvm-performance-x86_64-1', '--dir', temporary], role+'-historical-download')
                    for kind, destination in zip(('pvm-native', 'pvm-performance'), paths):
                        source = Path(temporary)/'tests'/kind/'results.json'
                        if not source.is_file() or source.is_symlink():
                            raise ValueError('Missing regular historical receipt: '+kind)
                        shutil.copyfile(source, destination)
            if any(path.is_symlink() or digest(path) != expected[key]
                   for path, key in zip(paths, ('native', 'performance'))):
                raise ValueError('Staged historical receipt digest mismatch: '+role)
            self.seal(paths)
            # Shallow Actions checkouts need the two sealed runtime commits, never a mutable branch ref.
            found = self.command(['git', 'cat-file', '-t', expected['runtime']], role+'-runtime-object',
                                 expected_failure=True)
            if found['exit_code']:
                self.command(['git', 'fetch', '--no-tags', '--depth=1', 'origin', expected['runtime']],
                             role+'-runtime-fetch')

    def source_snapshot(self, role, revision):
        """Extract exact Git-owned regular runtime files and adapt only the canonical driver imports."""
        if self.git('cat-file', '-t', revision) != b'commit\n':
            raise ValueError('Runtime selector is not an exact commit')
        for name in SHARED_FILES:
            if self.git('show', revision+':'+name) != (ROOT/name).read_bytes():
                raise ValueError('Runtime driver/header/pin differs from qualified orchestration: '+name)
        if role == 'candidate':
            for name in ('src', 'native/pvm_jit'):
                if self.git('rev-parse', revision+':'+name) != self.git('rev-parse', 'HEAD:'+name):
                    raise ValueError('Candidate runtime differs from current native-qualified sources')
        folder = self.folder/'snapshot'
        self.transient = {}
        if folder.is_symlink():
            raise ValueError('Runtime snapshot is redirected')
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir()
        data = self.git('archive', '--format=tar', revision, 'src', 'native/pvm_jit')
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            for member in archive.getmembers():
                # Exact source archives cannot redirect paths or import links/special files into the build.
                path = PurePosixPath(member.name)
                if path.is_absolute() or '..' in path.parts:
                    raise ValueError('Foreign runtime archive member')
                if member.isdir():
                    continue
                if not member.isfile() or not member.name.startswith(('src/', 'native/pvm_jit/')):
                    raise ValueError('Nonregular runtime archive member')
                target = folder/member.name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.extractfile(member).read())
        sources = {str(path.relative_to(folder)): digest(path)
                   for path in sorted(folder.rglob('*')) if path.is_file()}
        if not sources or not any(name.startswith('native/pvm_jit/') for name in sources):
            raise ValueError('Missing complete runtime/header archive')
        history = self.folder/'historical'/role
        provenance, performance = historical_binding(history/'native.json', history/'performance.json',
            PROVENANCE[role], sources, {name: digest(ROOT/name) for name in SHARED_FILES},
            digest(self.compiler), self.report['identity']['clang'])
        for path in self.inputs['sieve-1000']:
            # A canonical re-preparation must reproduce the exact previously qualified input/expected bytes.
            suffix = '/inputs/sieve/1000/'+path.name
            hashes = [value for name, value in performance['identity']['files'].items()
                      if name.endswith(suffix)]
            if hashes != [digest(path)]:
                raise ValueError('Canonical sieve1000 state differs from historical input: '+path.name)
        self.historical[role] = performance
        driver = folder/'tests/performance/pvm_sieve.nim'
        driver.parent.mkdir(parents=True)
        text = (ROOT/'tests/performance/pvm_sieve.nim').read_text()
        driver.write_text(snapshot_imports(text, folder/'src/pvm', '../../src/pvm/'))
        self.transient = {path: digest(path) for path in folder.rglob('*') if path.is_file()}
        self.report['runtime_sources'][role] = dict(revision=revision, files=sources,
            archive_sha256=hashlib.sha256(data).hexdigest(), driver_sha256=digest(driver),
            historical_qualification=provenance)
        self.checkpoint()
        return driver

    def build_image(self, role, driver, requests=False):
        """Capture one image's actual checked build, generated C and linked disassembly before reuse."""
        kind = 'requests' if requests else 'normal'
        name = role+'-'+kind
        cache = cache_directory(self.compiler, self.folder, 'engine')
        if cache.exists():
            shutil.rmtree(cache)
        defines = [*self.defines, 'pvmArm64JitOwnerReceipt', *(['pvmProfileRequests'] if requests else [])]
        flags = ['-I'+str(ROOT/'tests/performance'),
                 '-I'+str(self.folder/'snapshot/native/pvm_jit'), *(['-g'] if requests else [])]
        self.verify()
        row, binary = self.checks.build(self.compiler, driver, 'engine', defines=defines,
                                       cflags=flags, environment=execution_environment())
        # NativeChecks reuses engine-build.log: preserve completed failed builds before any exit/next build.
        saved_log = self.folder/(name+'-build.log')
        shutil.copyfile(ROOT/row['log'], saved_log)
        self.seal([saved_log])
        row = dict(row, log=str(saved_log.relative_to(ROOT)), log_sha256=digest(saved_log))
        self.verify()
        build = dict(runtime=role, kind=kind, source_revision=self.runtimes[role],
                     defines=defines, run=command_record(row))
        self.report['diagnostic_builds'].append(build)
        self.checkpoint()
        if row['exit_code'] or 'Error:' in row['output'] or 'FAILURE' in row['output']:
            raise RuntimeError('Attribution image build failed: '+name)
        image = self.folder/(name+'.elf')
        shutil.copy2(binary, image)
        archive, manifest = capture_generated_sources(self.folder, ROOT, 'engine')
        destination = self.folder/(name+'-generated-source')
        if destination.exists():
            shutil.rmtree(destination)
        archive.rename(destination)
        self.seal([image, *(destination/path for path in manifest)])
        symbols = self.command(['nm', '--defined-only', image], name+'-nm')
        symbol = selected_symbol(symbols['output'], 'runPreparedKernel')
        disassembly = self.command(['objdump', '--disassemble', '--line-numbers',
                                   '--no-show-raw-insn', image], name+'-disassembly')
        if ('file format elf64-x86-64' not in disassembly['output'] or
                '<'+symbol+'>:' not in disassembly['output'] or not re.search(
                    r'^\s*[0-9a-f]+:\s+[a-z][a-z0-9]*\b', disassembly['output'], re.M)):
            raise ValueError('Missing actual linked x86 wrapper disassembly')
        build.update(image_sha256=digest(image), image=str(image.relative_to(ROOT)),
                     generated_sources=manifest, generated_archive=str(destination.relative_to(ROOT)),
                     symbols=command_record(symbols), disassembly=command_record(disassembly),
                     wrapper_symbol=symbol)
        self.checkpoint()
        return image, symbol

    def profile(self, runtime, role, image, symbol, normal):
        """Use one diagnostic image for both passes, retain every dump, and discard parsed clocks."""
        self.images['guest'] = image
        args, environment, _ = self.invocation(CASE, role)
        reference = None
        for instructions in (False, True):
            name = runtime+'-'+role+('-machine' if instructions else '-line')
            self.verify()
            try:
                row, final = collect(self.checks, args[0], name, symbol, environment, 1200,
                    instructions=instructions, dump_symbols=(symbol,), executions=13,
                    requests=True, absolute_positions=True)
            finally:
                self.verify()
            if row['exit_code']:
                raise RuntimeError('Profile process failed: '+name)
            parsed = self.parse(row['output'], CASE, role)['sieve-1000']
            native = native_evidence(parsed, role)
            matching_native_activity(normal, native)
            parts = read_parts(final, instructions, reference)
            if any(not any(row['function'] == symbol for row in part['positions']+part['arcs'])
                   for part in parts):
                raise ValueError('Collected invocation lacks its actual linked public wrapper')
            if not instructions:
                reference = parts
            details = self.folder/(name+'-positions.json')
            details.write_text(json.dumps(parts, indent=2)+'\n')
            hashes = {path.name: digest(path) for path in sorted(self.folder.glob(name+'.callgrind*'))}
            self.seal([details, *(self.folder/path for path in hashes)])
            for index in (1, 13):
                self.command(['callgrind_annotate', '--auto=no', '--inclusive=no', '--tree=both',
                    '--threshold=99', '--show='+','.join(EVENTS),
                    self.folder/(name+'.callgrind.'+str(index))], name+'-'+str(index)+'-annotation')
            self.report['profiles'].append(dict(runtime=runtime, backend=role, machine=instructions,
                checked_calls=13, image_sha256=digest(image), native=native, raw_profiles=hashes,
                environment={key: value for key, value in environment.items()
                             if key.startswith('RAGNAROK_PVM_')},
                attribution=dict(path=details.name, sha256=digest(details)),
                invocation_counts=[part['counts'] for part in parts], run=command_record(row)))
            self.checkpoint()

    def execute(self):
        """Keep a partial diagnostic receipt on every failure and never call the timing publisher."""
        self.folder.mkdir(parents=True, exist_ok=True)
        summary = self.folder/'summary.md'
        summary.write_text('X86 attribution incomplete; clocks discarded; PR #1979 remains HOLD.\n')
        self.checkpoint()
        try:
            host = host_identity()
            if (os.environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch' or
                    host['system'] != 'Linux' or host['architecture'] != 'x86_64'):
                raise ValueError('Attribution requires an explicit manual Linux x86 diagnostic request')
            self.qualify()
            if os.environ.get('VALGRIND_LIB') or os.environ.get('VALGRIND_OPTS'):
                raise ValueError('Inherited Valgrind overrides cannot identify the documented collector')
            version = self.command(['valgrind', '--version'], 'valgrind-version')
            if version['output'].strip() != VERSION:
                raise ValueError('Attribution requires documented '+VERSION+'; no collector fallback')
            executable = Path(shutil.which('valgrind') or '').resolve()
            if not executable.is_file():
                raise ValueError('Cannot identify actual collector executable')
            self.seal([executable, ROOT/'tests/support/pvm_profile_control.c'])
            self.report['identity']['collector'] = dict(version=VERSION, sha256=digest(executable),
                package=self.command(['dpkg-query', '--show', '--showformat=${Version}',
                                      'valgrind'], 'valgrind-package')['output'])
            files = self.command(['dpkg-query', '--listfiles', 'valgrind'], 'valgrind-files')['output']
            tools = [Path(name) for name in files.splitlines()
                     if Path(name).name == 'callgrind-amd64-linux' and Path(name).is_file()]
            if len(tools) != 1:
                raise ValueError('Cannot uniquely identify actual Callgrind executable')
            self.seal(tools)
            self.report['identity']['collector']['callgrind_sha256'] = digest(tools[0])
            self.stage_inputs()
            calibrate_scope(self.checks, self.report, requests=True)
            self.verify()
            controls = self.report['controls']
            if (len(controls) != 4 or {row.get('name') for row in controls} !=
                    {'control-selected', 'control-absent', 'control-repeated', 'control-last-only'}
                    or any(row.get('passed') is not True for row in controls)):
                raise ValueError('Missing complete passed request calibration cohort')
            self.checkpoint()
            self.prepare_micro(diagnostic=True)
            for runtime, revision in self.runtimes.items():
                driver = self.source_snapshot(runtime, revision)
                normal, _ = self.build_image(runtime, driver)
                diagnostic, symbol = self.build_image(runtime, driver, requests=True)
                for role in ('interpreted', 'jit'):
                    # Preserve canonical live assertion/state refusals without duplicating the positive call.
                    self.images['guest'] = normal
                    start = len(self.report['controls'])
                    parsed = self.controls(CASE, role, name_prefix=runtime+'-')['sieve-1000']
                    for control in self.report['controls'][start:]:
                        control['runtime'] = runtime
                        self.seal([ROOT/control['run']['log']])
                    native = native_evidence(parsed, role)
                    self.report['normal_controls'].append(dict(runtime=runtime, backend=role,
                        image_sha256=digest(normal), native=native, checked_calls=13))
                    self.checkpoint()
                    self.profile(runtime, role, diagnostic, symbol, native)
            self.verify()
            self.report.update(status='passed', clock_policy='discarded')
            self.report['identity']['files'] = {str(path): value for path, value in self.seals.items()}
            self.checkpoint()
            summary.write_text('X86 instruction attribution passed: four sieve1000 cells, '
                '13 calls per process, both collector passes. Clocks discarded; '
                'no performance ratios or latest eligibility. PR #1979 remains HOLD.\n')
        except BaseException as error:
            # Do not delete failed raw evidence or retain a stale successful diagnostic summary.
            self.report.update(status='failed', error=str(error))
            self.checkpoint()
            summary.write_text('X86 attribution failed; clocks discarded; PR #1979 remains HOLD.\n'
                               +str(error).replace('\n', ' ')+'\n')
            raise
        return self.report
