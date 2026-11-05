# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Audit bounded attribution with inert tools and independent malformed/complete Callgrind witnesses."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import pvm_x86_attribution as attribution
from pvm_instruction_profile import exclusive_costs
import pvm_guest_inputs as guest_inputs
from pvm_guest_compare import unchanged
from pvm_performance_report import validate_report
from setup_nimony import cache_directory


def profile(machine=False, part=1, pid=123):
    """Literal self work totals15; the two-call inclusive edge costs5 and must not inflate that total."""
    positions = 'instr line' if machine else 'line'
    caller, target, callee = ('0x100 11', '0x200 20', '0x200 20') if machine else ('11', '20', '20')
    return ('# callgrind format\nversion: 1\npid: '+str(pid)+'\npart: '+str(part)
        +'\npositions: '+positions+'\nevents: Ir Bc Bcm Bi Bim\nsummary: 15 4 1 2 1\n'
        'ob=/sealed/image\nfl=generated.c\nfn=runPreparedKernel_0_test\n'
        +caller+' 10 3 1 1 0\ncfn=guard\ncalls=2 '+target+'\n'+caller+' 5 1 0 1 1\n'
        'fn=guard\n'+callee+' 5 1 0 1 1\ntotals: 15 4 1 2 1\n')


def dump_parts(folder, name, machine=False):
    """Write all13 distinct complete parts and a truly empty final process dump without a program."""
    base = folder/(name+'.callgrind')
    base.write_text('# callgrind format\nevents: Ir Bc Bcm Bi Bim\nsummary: 0\ntotals: 0\n')
    for index in range(1, 14):
        Path(str(base)+'.'+str(index)).write_text(profile(machine, index))
    return Path(str(base)+'.13')


def calibrated(checks, report, requests=False):
    """Supply independent complete calibration verdicts without compiling or running the control program."""
    if not requests:
        raise AssertionError('Request calibration was not selected')
    report['controls'].extend(dict(name=name, passed=True) for name in (
        'control-selected', 'control-absent', 'control-repeated', 'control-last-only'))


def parsed(role):
    """Independent positive native counters and conspicuous clocks make accidental timing publication visible."""
    native = dict(zip(attribution.NATIVE_FIELDS, (100, 20909, 99032, 3000, 20, 30)))
    if role == 'interpreted':
        native = dict.fromkeys(attribution.NATIVE_FIELDS, 0)
    return dict(native=dict(native, compile_ns=123456789),
                execution=dict(samples=[dict(cpu_ns=123456789, wall_ns=123456789)]*13))


def receipt_fixture(folder):
    """Construct independent historical source/qualification facts, including a distinct squash revision."""
    sources = {'src/pvm/step.nim': '1'*64, 'native/pvm_jit/x86_memory.h': '2'*64}
    shared = {'spec/toolchain.json': '3'*64, 'tests/performance/pvm_sieve.nim': '4'*64,
              'tests/performance/pvm_profile_scope.h': '5'*64}
    native = dict(status='passed', revision='b'*40, compiler_sha256='c'*64,
        host=dict(architecture='x86_64'), sources=sources.copy(),
        policies=dict(native_build_defines=['pvmX86Jit'], native_jit_available=True),
        qualification=[dict(name='all-opcodes', build=dict(exit_code=0), run=dict(exit_code=0))])
    files = {'/original/'+name: value for name, value in {**sources, **shared}.items()}
    performance = dict(schema='pvm-performance-v2', status='passed', revision='b'*40,
        identity=dict(files=files, ci=dict(GITHUB_RUN_ID='123', GITHUB_SHA='b'*40),
            host=dict(architecture='x86_64'), compiler=dict(sha256='c'*64),
            clang='qualified clang',
            native_qualification=dict(revision='b'*40)))
    return native, performance, sources, shared


def save_receipts(folder, native, performance):
    """Seal test transport bytes independently; semantic negative cases still need qualification/source checks."""
    npath, ppath = folder/'native.json', folder/'performance.json'
    ndata = json.dumps(native).encode()
    nhash = hashlib.sha256(ndata).hexdigest()
    performance['identity']['native_qualification']['sha256'] = nhash
    performance['identity']['files']['/original/build/tests/pvm-native/results.json'] = nhash
    pdata = json.dumps(performance).encode()
    npath.write_bytes(ndata)
    ppath.write_bytes(pdata)
    expected = dict(runtime='a'*40, revision='b'*40, run='123', native=nhash,
                    performance=hashlib.sha256(pdata).hexdigest())
    return npath, ppath, expected


class InertChecks:
    """Create stand-in build bytes at the real private-cache paths; never spawn any process."""

    def __init__(self, runner):
        """Keep only the current test runner and its isolated workspace."""
        self.runner = runner
        self.fail = False

    def build(self, compiler, source, name, defines=(), cflags=(), environment=None):
        """Expose actual flags and distinct normal/request C/ELF bytes to the production capture code."""
        kind = 'requests' if 'pvmProfileRequests' in defines else 'normal'
        cache = cache_directory(compiler, self.runner.folder, name)/'c'
        cache.mkdir(parents=True)
        (cache/'kernel.c').write_text('/* '+self.runner.active+' '+kind+' */\n')
        image = self.runner.folder/name
        image.write_text(self.runner.active+' '+kind)
        # Mirror NativeChecks.command's shared name-derived log, including completed compiler failures.
        log = self.runner.folder/(name+'-build.log')
        output = self.runner.active+' '+kind+' build '+('failed' if self.fail else 'passed')+'\n'
        log.write_text(output)
        return dict(command=['inert-compiler', *defines, *cflags], exit_code=1 if self.fail else 0, output=output,
                    log=str(log.relative_to(ROOT))), image


class InertRunner(attribution.AttributionRunner):
    """Exercise production build capture, mode scheduling, collection validation and publication inertly."""

    def __init__(self, folder):
        """Keep the real bounded selectors; only external source/tool/native boundaries are replaced."""
        super().__init__(folder, attribution.PROVENANCE['parent']['runtime'],
                         attribution.PROVENANCE['candidate']['runtime'])
        self.checks = InertChecks(self)
        self.compiler = folder/'compiler'
        self.compiler.write_text('inert compiler bytes')
        self.collector = folder/'callgrind-amd64-linux'
        self.collector.write_text('inert collector bytes')
        self.defines = ['pvmX86Jit']
        self.collected = []

    def qualify(self):
        """No prerequisite compiler/runtime is launched by this test boundary."""
        self.report['identity']['native_qualification'] = dict(revision='fresh-orchestration-head')

    def stage_inputs(self):
        """Remote artifacts/Git transport are forbidden in inert integration tests."""

    def prepare_micro(self, diagnostic=False):
        """Supply only the selected canonical input/expected pair, with no guest/reference execution."""
        if not diagnostic:
            raise AssertionError('Wider preparation reached by attribution')
        data, expected = self.folder/'input.bin', self.folder/'expected.bin'
        data.write_bytes(bytes(400))
        expected.write_bytes(bytes(400))
        self.inputs['sieve-1000'] = (data, expected)

    def source_snapshot(self, role, revision):
        """Provide a private dummy driver; historical source validation is checked independently."""
        self.active = role
        driver = self.folder/'snapshot/benchmarks/kernel.nim'
        driver.parent.mkdir(parents=True, exist_ok=True)
        driver.write_text('inert driver')
        return driver

    def command(self, arguments, name, env=None, timeout=900, expected_failure=False):
        """Return explicit collector/nm/disassembly witnesses and reject every unknown tool request."""
        args = [str(value) for value in arguments]
        if args[:2] == ['valgrind', '--version']:
            output = attribution.VERSION+'\n'
        elif args[0] == 'dpkg-query':
            output = str(self.collector)+'\n' if '--listfiles' in args else '1:3.26.0-test'
        elif args[0] == 'nm':
            output = '0000000000000100 T runPreparedKernel_0_test\n'
        elif args[0] == 'objdump':
            output = 'file format elf64-x86-64\n100 <runPreparedKernel_0_test>:\n 100: ret\n'
        elif args[0] == 'callgrind_annotate':
            output = '15 PROGRAM TOTALS\n'
        else:
            raise AssertionError('Unexpected external command: '+str(args))
        log = self.folder/(name+'.log')
        log.write_text(output)
        return dict(command=args, output=output, exit_code=0, log=str(log.relative_to(ROOT)))

    def controls(self, case, role, name_prefix=''):
        """Stand in for the already-tested canonical assertion/state controls and their positive parse."""
        if self.images['guest'].read_text() != self.active+' normal':
            raise AssertionError('Normal control used instrumented image')
        log = self.folder/(name_prefix+role+'-positive.log')
        log.write_text('inert normal full-state control')
        self.report['controls'].append(dict(kind='positive', run=dict(log=str(log.relative_to(ROOT)))))
        return {'sieve-1000': parsed(role)}

    def parse(self, output, case, role):
        """Replace native wire assertions with controlled counter fixtures, never a real VM."""
        return {'sieve-1000': parsed(role)}


class AttributionTests(unittest.TestCase):
    """Malformed counts/positions/provenance or scope drift cannot produce accepted diagnostics."""

    def setUp(self):
        """Keep all temporary capture paths inside the actual owned build root."""
        (ROOT/'build').mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='inert-x86-attribution-', dir=ROOT/'build')
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)

    def test_exclusive_arcs_and_instruction_positions(self):
        """Positive and zero-call inclusive ancestry never inflate independently known self work."""
        for machine in (False, True):
            for count in ('2', '0'):
                result = attribution.positioned_costs(profile(machine).replace('calls=2 ', 'calls='+count+' '), machine)
                self.assertEqual(result['counts'], dict(Ir=15, Bc=4, Bcm=1, Bi=2, Bim=1))
                self.assertEqual(result['self_costs']['guard']['Ir'], 5)
                self.assertEqual(result['self_costs']['runPreparedKernel_0_test']['Ir'], 10)
                self.assertEqual(result['arcs'][0]['calls'], int(count))
                self.assertEqual(result['positions'][1]['position'], [512, 20] if machine else [20])
        with self.assertRaises(ValueError):
            exclusive_costs(profile(True))

    def test_refuses_partial_nonconserving_or_compressed_costs(self):
        """Complete footers alone cannot certify malformed, overflowing or missing self/arc records."""
        original = profile(True)
        bad = [original.replace('summary: 15', 'summary: 16'),
               original.replace('summary: 15', 'summary: 16').replace('totals: 15', 'totals: 16'),
               original.replace('0x100 11 10', '+1 11 10'),
               original.replace('0x100 11 10', '0x100 * 10'),
               original.replace('0x100 11 10', '0x100 11 -1'),
               original.replace('0x100 11 10', '0x10000000000000000 11 10'),
               original.replace('calls=2 0x200 20', 'calls=2 0x200'),
               original.replace('cfn=guard\n', ''),
               original.replace('fn=guard\n0x200', 'fn=(1)\n0x200'),
               original.replace('0x100 11 5 1 0 1 1\n', ''),
               original+'calls=1 0x100 11\n',
               original.replace('events: Ir Bc', 'events: Ir Ir Bc')]
        for text in bad:
            with self.subTest(text=text[-120:]), self.assertRaises(ValueError):
                attribution.positioned_costs(text, True)

    def test_uncompressed_parenthesized_ancestry_preserves_exclusive_work(self):
        """Callgrind's ordinary ancestry name is valid; its zero-call inclusive arc is not additional self work."""
        text = profile().replace('totals: 15',
            'fn=(below main)\ncfn=runPreparedKernel_0_test\ncalls=0 11\n'
            '0 15 4 1 2 1\ntotals: 15')
        result = attribution.positioned_costs(text)
        self.assertEqual(result['counts'], dict(Ir=15, Bc=4, Bcm=1, Bi=2, Bim=1))
        self.assertEqual(sum(row['Ir'] for row in result['self_costs'].values()), 15)
        self.assertEqual(result['arcs'][-1]['function'], '(below main)')
        self.assertEqual(result['arcs'][-1]['calls'], 0)

    def test_cross_object_call_targets_persist_until_rebound(self):
        """Shared-library target metadata must not silently become the caller's object after a function change."""
        text = profile(True).replace('cfn=guard\n', 'cob=/lib/runtime.so\ncfi=runtime.c\ncfn=guard\n')
        text = text.replace('totals: 15', 'fn=another_caller\ncalls=0 0x200 20\n'
                            '0x400 40 0\ntotals: 15')
        arcs = attribution.positioned_costs(text, True)['arcs']
        self.assertEqual(arcs[-1]['callee_object'], '/lib/runtime.so')
        self.assertEqual(arcs[-1]['callee_file'], 'runtime.c')
        self.assertEqual(arcs[-1]['callee'], 'guard')

    def test_all_parts_empty_final_and_cross_pass_events(self):
        """Audit warmups, numbering and all events, not just the final part or matching Ir."""
        line = dump_parts(self.folder, 'line')
        machine = dump_parts(self.folder, 'machine', True)
        reference = attribution.read_parts(line)
        self.assertEqual(len(attribution.read_parts(machine, True, reference)), 13)
        seven = self.folder/'machine.callgrind.7'
        seven.write_text(profile(True, 7, pid=456))
        with self.assertRaises(ValueError):
            attribution.read_parts(machine, True, reference)
        seven.write_text(profile(True, 8))
        with self.assertRaises(ValueError):
            attribution.read_parts(machine, True, reference)
        seven.write_text(profile(True, 7).replace('15 4 1 2 1', '15 5 1 2 1')
                         .replace('10 3 1 1 0', '10 4 1 1 0'))
        with self.assertRaises(ValueError):
            attribution.read_parts(machine, True, reference)
        seven.unlink()
        with self.assertRaises(ValueError):
            attribution.read_parts(machine, True, reference)
        dump_parts(self.folder, 'machine', True)
        (self.folder/'machine.callgrind').write_text(
            '# callgrind format\nevents: Ir Bc Bcm Bi Bim\nsummary: 0 1\ntotals: 0 1\n')
        with self.assertRaises(ValueError):
            attribution.read_parts(machine, True, reference)

    def test_native_acceptance_discards_clocks_and_refuses_fallback(self):
        """All six observed native fields and thirteen calls are required without admitting compilation clocks."""
        self.assertEqual(attribution.native_evidence(parsed('interpreted'), 'interpreted'),
                         dict.fromkeys(attribution.NATIVE_FIELDS, 0))
        self.assertEqual(attribution.native_evidence(parsed('jit'), 'jit')['calls'], 20909)
        self.assertNotIn('compile_ns', attribution.native_evidence(parsed('jit'), 'jit'))
        cases = [(parsed('interpreted'), 'jit'), (parsed('jit'), 'interpreted')]
        short = parsed('jit')
        short['execution']['samples'].pop()
        cases.append((short, 'jit'))
        boolean = parsed('jit')
        boolean['native']['fragments'] = True
        cases.append((boolean, 'jit'))
        for values, role in cases:
            with self.assertRaises(ValueError):
                attribution.native_evidence(values, role)

    def test_only_sealed_runtime_pair_and_micro_are_admitted(self):
        """Mutable, option-like, reversed or unrelated refs must fail before external tools are reachable."""
        parent, candidate = (attribution.PROVENANCE[key]['runtime'] for key in ('parent', 'candidate'))
        for left, right, scope in [('master', candidate, 'micro'), ('--help', candidate, 'micro'),
                (parent+';false', candidate, 'micro'), (parent, 'f'*40, 'micro'),
                (candidate, parent, 'micro'), (parent, candidate, 'all')]:
            with self.assertRaises(ValueError):
                attribution.AttributionRunner(self.folder, left, right, scope=scope)

    def test_historical_receipts_preserve_original_revision_and_require_actual_source_qualification(self):
        """Successful transport cannot relabel a squash or excuse changed source, pins, compiler or qualification."""
        native, performance, sources, shared = receipt_fixture(self.folder)
        npath, ppath, expected = save_receipts(self.folder, native, performance)
        binding, _ = attribution.historical_binding(npath, ppath, expected, sources, shared,
                                                   'c'*64, 'qualified clang')
        self.assertEqual(binding['runtime_revision'], 'a'*40)
        self.assertEqual(binding['qualification_revision'], 'b'*40)
        for source, config, compiler in [({**sources, 'src/pvm/step.nim': '9'*64}, shared, 'c'*64),
                (sources, {**shared, 'spec/toolchain.json': '9'*64}, 'c'*64),
                (sources, shared, 'd'*64)]:
            with self.assertRaises(ValueError):
                attribution.historical_binding(npath, ppath, expected, source, config, compiler,
                                                'qualified clang')
        with self.assertRaises(ValueError):
            attribution.historical_binding(npath, ppath, expected, sources, shared, 'c'*64, 'changed clang')
        # Re-sealing independent negative witnesses tests qualification checks beyond the outer digest gate.
        bad = []
        failed = deepcopy(native)
        failed['qualification'][0]['run']['exit_code'] = 1
        bad.append((failed, deepcopy(performance)))
        missing = deepcopy(native)
        missing['sources'].pop('src/pvm/step.nim')
        bad.append((missing, deepcopy(performance)))
        relabeled = deepcopy(performance)
        relabeled['revision'] = 'a'*40
        bad.append((deepcopy(native), relabeled))
        unfinished = deepcopy(native)
        unfinished['status'] = 'incomplete'
        bad.append((unfinished, deepcopy(performance)))
        wrong_run = deepcopy(performance)
        wrong_run['identity']['ci']['GITHUB_RUN_ID'] = '456'
        bad.append((deepcopy(native), wrong_run))
        for nvalue, pvalue in bad:
            npath, ppath, expected = save_receipts(self.folder, nvalue, pvalue)
            with self.assertRaises(ValueError):
                attribution.historical_binding(npath, ppath, expected, sources, shared, 'c'*64,
                                                'qualified clang')
        npath.write_text('changed bytes')
        with self.assertRaises(ValueError):
            attribution.historical_binding(npath, ppath, expected, sources, shared, 'c'*64,
                                            'qualified clang')

    def test_diagnostic_preparer_executes_only_sieve1000_and_keeps_fixture_expected_seals(self):
        """The canonical preparer must retain source and complete expected-state checks for its narrow selection."""
        root = self.folder/'repository'
        files = ['tests/performance/polkavm_backend.rs', 'spec/polkavm-pins.json',
                 'spec/toolchain.json', 'spec/bandersnatch-pins.json', 'Makefile',
                 'crate/Cargo.toml', 'crate/Cargo.lock', 'crate/src/main.rs',
                 'target/release/ragnarok-pvm-benchmark', 'fixtures/sieve.polkavm']
        for name in files:
            path = root/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture bytes')
        (root/'spec/polkavm-pins.json').write_text('{}')
        (root/'spec/bandersnatch-pins.json').write_text('{"rust":"pinned-test"}')
        fixture = root/'fixtures/sieve.polkavm'
        contract = (None, fixture.parent, [(fixture, hashlib.sha256(b'fixture bytes').hexdigest())])
        calls = []
        empty_expected = False

        class Checks:
            """Emulate only a pinned reference build and the expected-state preparation CLI."""

            def command(self, arguments, name, **options):
                """Write complete state files unless the missing-expected negative witness is selected."""
                calls.append(list(arguments))
                if '--sieve-prepare' in arguments:
                    destination = Path(arguments[3])
                    (destination/'input-1000.bin').write_bytes(b'input witness')
                    (destination/'expected-1000.bin').write_bytes(b'' if empty_expected else b'expected witness')
                    output = 'SIEVE_PREPARED,1000,1,64\n'
                else:
                    output = ''
                return dict(exit_code=0, output=output, log='inert.log')

        with patch.object(guest_inputs, 'ROOT', root), \
                patch.object(guest_inputs, 'CRATE', root/'crate'), \
                patch.object(guest_inputs, 'TARGET', root/'target'), \
                patch.object(guest_inputs, 'load_fixture_contracts', return_value={
                    key: contract for key in ('pvm_guests', 'pvm_pinky', 'pvm_sieve')}), \
                patch.object(guest_inputs, 'require_submodule', return_value=root/'upstream'), \
                patch.object(guest_inputs, 'verify_fixture', return_value={'pinned': True}):
            with self.assertRaises(ValueError):
                guest_inputs.prepare_inputs(Checks(), root/'ordinary', cases=(('sieve', 1000),))
            self.assertEqual(calls, [])
            prepared = guest_inputs.prepare_inputs(Checks(), root/'inputs',
                                                  cases=(('sieve', 1000),), diagnostic=True)
            selected = [row for row in calls if '--sieve-prepare' in row]
            self.assertEqual(len(selected), 1)
            self.assertEqual(selected[0][-2:], [1000, 1])
            self.assertEqual(prepared['inputs'][0][:2], ('sieve', 1000))
            expected = prepared['inputs'][0][3]
            expected.write_text('changed expected state')
            with self.assertRaises(ValueError):
                unchanged(prepared['identities'])
            empty_expected = True
            with self.assertRaises(ValueError):
                guest_inputs.prepare_inputs(Checks(), root/'empty-inputs',
                                           cases=(('sieve', 1000),), diagnostic=True)
            fixture.write_text('changed pinned source')
            before = len(calls)
            with self.assertRaises(ValueError):
                guest_inputs.prepare_inputs(Checks(), root/'changed-inputs',
                                           cases=(('sieve', 1000),), diagnostic=True)
            self.assertEqual(len(calls), before)

    def test_complete_inert_collection_uses_four_images_and_cannot_publish_timings(self):
        """The real capture/profile path conserves all13 dumps and shares each image across policies/passes."""
        runner = InertRunner(self.folder)
        used = []

        def collected(checks, binary, name, scope, environment, timeout, **options):
            """Produce raw independent witnesses and record actual shared image bytes, never run a program."""
            used.append((name, Path(binary).read_text(), options))
            final = dump_parts(self.folder, name, options['instructions'])
            log = self.folder/(name+'.log')
            log.write_text('inert instrumented clocks are discarded')
            return dict(output='inert protocol', exit_code=0, command=['inert-callgrind', str(binary)],
                        log=str(log.relative_to(ROOT))), final

        with patch.object(attribution, 'host_identity', return_value=dict(system='Linux', architecture='x86_64')), \
                patch.dict('os.environ', GITHUB_EVENT_NAME='workflow_dispatch'), \
                patch.object(attribution.shutil, 'which', return_value=str(runner.collector)), \
                patch.object(attribution, 'calibrate_scope', calibrated), \
                patch.object(attribution, 'collect', collected):
            result = runner.execute()
        self.assertEqual(result['status'], 'passed')
        self.assertEqual(result['schema'], 'pvm-x86-attribution-v1')
        self.assertEqual(len(result['diagnostic_builds']), 4)
        self.assertEqual({(row['runtime'], row['kind']) for row in result['diagnostic_builds']},
                         {('parent', 'normal'), ('parent', 'requests'),
                          ('candidate', 'normal'), ('candidate', 'requests')})
        self.assertEqual(len(used), 8)
        self.assertEqual({image for _, image, _ in used}, {'parent requests', 'candidate requests'})
        self.assertTrue(all(options['requests'] and options['absolute_positions'] for _, _, options in used))
        self.assertTrue(all(len(row['raw_profiles']) == 14 for row in result['profiles']))
        self.assertEqual(sum(row['checked_calls'] for row in result['profiles']+result['normal_controls']), 156)
        self.assertNotIn('cpu_ns', json.dumps(result))
        self.assertNotIn('123456789', json.dumps(result))
        self.assertFalse((self.folder/'samples.csv').exists())
        with self.assertRaises(ValueError):
            validate_report(result)
        for build in result['diagnostic_builds']:
            # Captured C must survive subsequent private-cache reuse with its own sealed bytes.
            path = ROOT/build['generated_archive']
            self.assertEqual({attribution.digest(path/name) for name in build['generated_sources']},
                             {entry['sha256'] for entry in build['generated_sources'].values()})

    def test_build_receipts_retain_exact_logs_after_shared_log_overwrites_including_failure(self):
        """Every earlier receipt must retain its own immutable output after later builds replace the shared log."""
        runner = InertRunner(self.folder)
        retained = []
        cases = (('parent', False, False, b'parent normal build passed\n'),
                 ('parent', True, True, b'parent requests build failed\n'),
                 ('candidate', False, False, b'candidate normal build passed\n'),
                 ('candidate', True, False, b'candidate requests build passed\n'))
        for role, requests, failed, expected in cases:
            # Continue explicitly in this inert witness to prove even a failed receipt survives later writes.
            driver = runner.source_snapshot(role, attribution.PROVENANCE[role]['runtime'])
            runner.checks.fail = failed
            if failed:
                with self.assertRaises(RuntimeError):
                    runner.build_image(role, driver, requests)
            else:
                runner.build_image(role, driver, requests)
            build = runner.report['diagnostic_builds'][-1]
            retained.append((ROOT/build['run']['log'], expected, build['run']))
            self.assertEqual(build['run']['exit_code'], 1 if failed else 0)
            self.assertEqual((self.folder/'engine-build.log').read_bytes(), expected)
            for path, original, _ in retained:
                self.assertEqual(path.read_bytes(), original)
            runner.verify()
        for _, original, receipt in retained:
            self.assertEqual(hashlib.sha256(original).hexdigest(), receipt['log_sha256'])

    def test_invalid_collection_retains_raw_failure_and_retires_success(self):
        """A malformed intermediate invocation cannot inherit an earlier successful report or erase its raw bytes."""
        for kind in ('partial', 'unrelated-wrapper'):
            # Complete but unrelated work is as invalid as a truncated warmup; keep both raw witnesses.
            folder = self.folder/kind
            folder.mkdir()
            runner = InertRunner(folder)
            (folder/'results.json').write_text('{"status":"passed"}')
            witness = ('incomplete raw profile witness' if kind == 'partial' else
                       profile(part=7).replace('runPreparedKernel_0_test', 'unrelated_function'))

            def broken(checks, binary, name, scope, environment, timeout, **options):
                """Retain a concrete wrong warmup witness, never invoke the guest or collector."""
                final = dump_parts(folder, name, options['instructions'])
                (folder/(name+'.callgrind.7')).write_text(witness)
                return dict(exit_code=0, output='inert protocol'), final

            with patch.object(attribution, 'host_identity', return_value=dict(system='Linux', architecture='x86_64')), \
                    patch.dict('os.environ', GITHUB_EVENT_NAME='workflow_dispatch'), \
                    patch.object(attribution.shutil, 'which', return_value=str(runner.collector)), \
                    patch.object(attribution, 'calibrate_scope', calibrated), \
                    patch.object(attribution, 'collect', broken):
                with self.assertRaises(ValueError):
                    runner.execute()
            report = json.loads((folder/'results.json').read_text())
            self.assertEqual(report['status'], 'failed')
            self.assertEqual((folder/'parent-interpreted-line.callgrind.7').read_text(), witness)
            self.assertIn('failed', (folder/'summary.md').read_text())

    def test_incomplete_calibration_or_wrong_host_cannot_collect(self):
        """Scope success must come from the complete actual-host request control cohort."""
        runner = InertRunner(self.folder)
        with patch.object(attribution, 'host_identity', return_value=dict(system='Linux', architecture='arm64')), \
                patch.dict('os.environ', GITHUB_EVENT_NAME='workflow_dispatch'), \
                patch.object(attribution, 'collect', side_effect=AssertionError('collector reached')):
            with self.assertRaises(ValueError):
                runner.execute()
        with patch.object(attribution, 'host_identity', return_value=dict(system='Linux', architecture='x86_64')), \
                patch.dict('os.environ', GITHUB_EVENT_NAME='workflow_dispatch'), \
                patch.object(attribution.shutil, 'which', return_value=str(runner.collector)), \
                patch.object(attribution, 'calibrate_scope'), \
                patch.object(attribution, 'collect', side_effect=AssertionError('collector reached')):
            with self.assertRaises(ValueError):
                runner.execute()
        self.assertEqual(json.loads((self.folder/'results.json').read_text())['status'], 'failed')

    def test_legacy_collector_version_has_no_fallback(self):
        """The older whole-profiler's3.22 version must never be silently accepted for this collection."""
        runner = InertRunner(self.folder)
        original = runner.command

        def legacy(arguments, name, **options):
            """Expose a concrete unsupported installed collector without spawning it."""
            row = original(arguments, name, **options)
            if name == 'valgrind-version':
                row['output'] = 'valgrind-3.22.0\n'
            return row

        with patch.object(attribution, 'host_identity', return_value=dict(system='Linux', architecture='x86_64')), \
                patch.dict('os.environ', GITHUB_EVENT_NAME='workflow_dispatch'), \
                patch.object(runner, 'command', legacy), \
                patch.object(attribution, 'collect', side_effect=AssertionError('collector reached')):
            with self.assertRaisesRegex(ValueError, '3.26.0'):
                runner.execute()


if __name__ == '__main__':
    unittest.main()
