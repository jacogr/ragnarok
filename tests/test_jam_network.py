# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent preset/whole-map boundaries and strict readiness, packaging and CI failure controls."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from harness_fixtures import make_plan
from workflow_fixtures import event_context, family_section, commands, artifact_paths
from unittest.mock import patch
from types import SimpleNamespace
import check_jam_network as network
import jam_fuzzer_network_oracle as reference
import jam_fuzzer_full_profile_oracle as full
from current_stf_oracle import Reader, decode_checkpoint
from state_layout_oracle import chapter_key
from state_statistics_oracle import parse as statistics_parse

ROOT = network.ROOT


class NetworkPreset(unittest.TestCase):
    """Verify independent geometry and delayed population changes without relying on a native observed successor."""

    @classmethod
    def setUpClass(cls):
        """Calculate the source-owned stream once and enforce its preexisting immutable pins."""
        _,cls.lines,cls.evidence = reference.expected_observations()

    def test_exact_nine_full_overrides(self):
        """Unchanged Full constants, six-second clock and both gas widths survive preset selection."""
        changed = {index:(before,after) for index,(before,after) in enumerate(zip(full.VALUES,reference.VALUES)) if before != after}
        self.assertEqual(changed,{3:(341,85),4:(19200,900),5:(600,60),8:(5000000000,1250000000),
                                  9:(3500000000,875000000),13:(16,4),14:(14400,600),18:(10,5),28:(500,50)})
        self.assertEqual(len(reference.parameters()),122)
        self.assertIn('existsEnv("JAM_FUZZ")',(ROOT/'src/ragnarok.nim').read_text())

    def test_delayed_population_and_complete_maps(self):
        """Both ordinary/skipped crossings activate old pending first, retaining prior population statistics exactly."""
        seeds = []; chains = []; current = None
        for line in self.lines:
            tag,raw = line.split(' ',1)
            if tag == 'P':
                current = []; chains.append(current); seeds.append(decode_checkpoint(bytes.fromhex(raw)))
            elif tag == 'O':
                current.append(decode_checkpoint(bytes.fromhex(raw)))
        self.assertEqual(len(chains),17)
        for ordinal,chain in enumerate(chains[:4]):
            population = 252 if ordinal < 2 else 6
            for state in chain:
                slot = int.from_bytes(state[chapter_key(11)],'little')
                current = Reader(state[chapter_key(8)]).count(); previous = Reader(state[chapter_key(9)]).count()
                activation = 120 if ordinal % 2 == 0 else 180
                self.assertEqual(current,population if slot >= activation else 255)
                self.assertEqual(set(state),set(seeds[ordinal]))
                self.assertEqual(len(state[chapter_key(14)]),60)
                parsed,consumed = statistics_parse(state[chapter_key(13)],(85,current,previous,2**64-1,2**64-1))
                self.assertEqual(consumed,len(state[chapter_key(13)]))
                self.assertEqual((len(parsed[0]),len(parsed[1]),len(parsed[2])),(current,previous,85))
        self.assertEqual(sum(map(len,chains[:4])),20)

    def test_strict_fuzz_expiry_and_rollback(self):
        """D900 equality retains removed history; D901 deletes or compacts with exact rollback semantics."""
        traces = self.evidence['expiry_traces']
        for index,mode in enumerate(('expire','restore','live','panic','checkpoint-panic')):
            exact,later = traces[2*index][0],traces[2*index+1][0]
            self.assertEqual((exact['slot'],later['slot']),(932,933))
            self.assertFalse(exact['deleted'])
            self.assertEqual(later['deleted'],mode in ('expire','checkpoint-panic'))
            if mode == 'restore': self.assertEqual(later['after'],[933,933])
            if mode == 'panic': self.assertEqual(later['after'],[0,32])

    def test_policy_binds_consensus_and_lookup_horizon(self):
        """Host policy must not accidentally retain Full consensus constants or the fixture's16-header retention."""
        text = (ROOT/'src/app/fuzz/policy.nim').read_text().split('"""',2)[1]
        replacements = dict(cores=85,validators=255,epoch=60,tickets=4,tail=50,rotation=5,lookup=600,
            blockGas=875000000,reportGas=10000000,queueHashes=6800,historyPackages=680,
            projectionRows=510,comparisons=65025,ancestors=601)
        for token,value in replacements.items(): text = text.replace('@'+token+'@',str(value))
        values = dict(line.split('=',1) for line in text.splitlines() if '=' in line)
        expected = {'candidate.reporting.admission.frame.cores':'85',
            'candidate.reporting.admission.frame.validators':'255',
            'candidate.reporting.admission.frame.epochSlots':'60',
            'candidate.reporting.admission.frame.ticketLimit':'4',
            'candidate.reporting.safrole.tailStart':'50',
            'candidate.reporting.reports.credentials.assignments.rotationSlots':'5',
            'candidate.reporting.reports.anchors.lookupAge':'600',
            'candidate.reporting.reports.ancestors.headers':'601',
            'candidate.round.blockGas':'875000000'}
        self.assertEqual({key:values[key] for key in expected},expected)


class NetworkReadiness(unittest.TestCase):
    """Partial, substituted or failed observations cannot supply a ready target or a live campaign pass."""

    def valid(self):
        """Construct an explicit positive runner control, with independent corpus and socket evidence."""
        digest = json.loads(reference.FIXTURE.read_text())['expected_sha256']
        row = dict(passed=True,expected_sha256=digest,actual_sha256=digest,build={'exit_code':0},run={'exit_code':0})
        return dict(cases={name:copy.deepcopy(row) for name in network.CORPORA.tasks},socket=dict(
            passed=True,sessions=17,completed_sessions=17,signed_imports=67,completed_imports=67,
            consensus_rejections=67,expected_state_queries=171,complete_state_queries=171,isolated_reconnects=1,guest_siblings=3,retained_siblings=3))

    def test_missing_failed_partial_and_tampered_evidence(self):
        """Retain failure controls for missing native stages, whole-map mismatch and incomplete actual exchanges."""
        good = self.valid(); self.assertTrue(network.complete(good))
        for field in ('completed_imports','completed_sessions','complete_state_queries','consensus_rejections','isolated_reconnects','retained_siblings'):
            altered = copy.deepcopy(good); altered['socket'][field] -= 1
            self.assertFalse(network.complete(altered))
        self.assertFalse(network.complete(dict(cases={},socket=good['socket'])))
        with patch.dict(network.CORPORA.tasks,{},clear=True):
            self.assertFalse(network.complete(dict(cases={},socket=good['socket'])))
        for field,value in (('actual_sha256','0'*64),('run',{'exit_code':1}),('build',{})):
            altered = copy.deepcopy(good); next(iter(altered['cases'].values()))[field] = value
            self.assertFalse(network.complete(altered))

    def test_failed_prerequisite_replaces_stale_success(self):
        """A failed invocation writes fresh failed results and keeps live engine status pending."""
        with tempfile.TemporaryDirectory() as folder:
            build = Path(folder)
            (build/'results.json').write_text('{"status":"checks-passed"}')
            with patch.object(network,'BUILD',build),patch.object(network,'installed',side_effect=OSError('missing compiler')),patch.object(network,'announce'):
                self.assertEqual(network.main(),1)
            observed = json.loads((build/'results.json').read_text())
            self.assertEqual(observed['status'],'failed'); self.assertEqual(observed['engine_validation'],'pending')
            self.assertFalse(network.complete(observed))
            self.assertIn('not a live campaign verdict',(build/'summary.md').read_text())

    def test_bundle_enters_shared_runtime_provenance(self):
        """Policy, parameters and entry point must be attributed just like the executable sources."""
        from runtime_provenance import runtime_sources
        paths = {str(path.relative_to(ROOT)) for path in runtime_sources()}
        for name in ('src/app/fuzz/policy.nim','src/app/fuzz/target.nim'):
            self.assertIn(name,paths)

    def test_matrix_keeps_target_and_testnet_separate(self):
        """The Fuzz aggregate requires its independent Network child; E2E/Testnet keeps its own runner."""
        workflow = (ROOT/'.github/workflows/ci.yml').read_text()
        section=family_section(workflow,'pvm-fuzz','jam-network',context=event_context())
        self.assertIn('make check-jam-network',commands(section))
        self.assertNotIn('make check-jam-fuzzer-interface',commands(section))
        self.assertNotIn('make check-e2e',commands(section))
        self.assertIn('build/tests/jam-network/*.json',artifact_paths(section))
        self.assertIn('tools/check_jam_network.py',make_plan('check-jam-network',skip=('setup','check-inventory')))

    def test_container_uses_environment_only_ordinary_binary(self):
        """The preset image inherits the normal binary entry point with no required flags or external policy assets."""
        source = (ROOT/'Dockerfile').read_text()
        self.assertEqual(source.count('ENTRYPOINT '),1)
        self.assertIn('ENTRYPOINT ["/usr/local/bin/ragnarok"]',source)
        self.assertIn('FROM runtime AS fuzz-target',source)
        self.assertIn('CMD []',source)
        self.assertNotIn('--fuzz-policy',source)
        self.assertFalse((ROOT/'tools/jam_fuzz_entrypoint.sh').exists())
        runner = (ROOT/'tools/check_jam_network.py').read_text()
        self.assertIn('arguments = [str(binary)]',runner)
        self.assertIn("JAM_FUZZ='1'",runner)
        self.assertNotIn('jam_fuzz_entrypoint',runner)


class NetworkStartup(unittest.TestCase):
    """Startup probes retain exact refusals and diagnostics without executing a native target locally."""

    def environment(self):
        """Supply only the public configuration keys needed by the preflight controls."""
        return dict(JAM_FUZZ='1',JAM_FUZZ_SPEC='fuzz',JAM_FUZZ_DATA_PATH='/unused',JAM_FUZZ_SOCK_PATH='/unused.sock')

    def reply(self,arguments,**options):
        """Model the established public CLI boundary independently from probe classification."""
        extra = arguments[1:]
        if not extra:
            return SimpleNamespace(returncode=2,stdout=b'',stderr=b'FUZZ_START_FAILED environment overrides\n')
        if extra == ['--version']:
            return SimpleNamespace(returncode=0,stdout=b'Ragnarok fixture\n',stderr=b'')
        if extra[0].startswith('--'):
            return SimpleNamespace(returncode=2,stdout=b'',stderr=('Unknown option: '+extra[0]+'\n').encode())
        return SimpleNamespace(returncode=2,stdout=b'',stderr=b'Unknown command: not-a-command; use ragnarok --help\n')

    def test_complete_startup_receipts(self):
        """All missing-environment, option, command and positive version controls leave bounded evidence."""
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); evidence = root/'evidence'; evidence.mkdir()
            with patch.object(network.subprocess,'run',side_effect=self.reply) as run:
                network.startup_checks(['/peer'],self.environment(),evidence,root/'target.sock')
            self.assertEqual(run.call_count,7)
            self.assertEqual({p.stem for p in evidence.glob('*.json')},
                {'missing-jam_fuzz_spec','missing-jam_fuzz_data_path','missing-jam_fuzz_sock_path',
                 'legacy-option','unknown-option','unknown-command','version'})
            self.assertEqual(json.loads((evidence/'legacy-option.json').read_text())['stderr'],
                             'Unknown option: --fuzz\n')
            self.assertEqual(json.loads((evidence/'version.json').read_text())['exit_code'],0)

    def test_wrong_refusal_keeps_receipt(self):
        """Unrelated crashes, wrong status and extra diagnostics never satisfy a negative control."""
        for status,message in ((1,b'Unknown option: --fuzz'),(2,b'Segmentation fault'),
                               (2,b'Unknown option: --fuzz\nextra')):
            with self.subTest(status=status,message=message), tempfile.TemporaryDirectory() as folder:
                root = Path(folder); evidence = root/'evidence'; evidence.mkdir()
                def reply(arguments,**options):
                    # Corrupt only the legacy-option result; preceding missing-environment controls still pass.
                    if arguments[1:] == ['--fuzz']:
                        return SimpleNamespace(returncode=status,stdout=b'',stderr=message)
                    return self.reply(arguments,**options)
                with patch.object(network.subprocess,'run',side_effect=reply), self.assertRaisesRegex(
                        AssertionError,'legacy-option'):
                    network.startup_checks(['/peer'],self.environment(),evidence,root/'target.sock')
                observed = json.loads((evidence/'legacy-option.json').read_text())
                self.assertEqual((observed['exit_code'],observed['stderr']),(status,message.decode()))

    def test_startup_timeout_keeps_bounded_output(self):
        """A stalled probe records its partial output and remains an error before any listener work."""
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            error = network.subprocess.TimeoutExpired(['/peer'],30,output=b'x'*5000,stderr=b'partial')
            with patch.object(network.subprocess,'run',side_effect=error), self.assertRaises(
                    network.subprocess.TimeoutExpired):
                network.startup_checks(['/peer'],self.environment(),root,root/'target.sock')
            observed = json.loads((root/'missing-jam_fuzz_spec.json').read_text())
            self.assertEqual(observed,dict(exit_code=124,stdout='x'*4000,stderr='partial'))
