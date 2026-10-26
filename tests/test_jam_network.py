# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent preset/whole-map boundaries and strict readiness, packaging and CI failure controls."""
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
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
        self.assertIn('serve-fuzz-preset',(ROOT/'tools/jam_fuzz_entrypoint.sh').read_text())

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
        values = dict(line.split('=',1) for line in (ROOT/'config/jam-fuzz-policy.conf').read_text().splitlines() if '=' in line and not line.startswith('#'))
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
        for name in ('config/jam-fuzz-policy.conf','tools/jam_fuzz_entrypoint.sh'):
            self.assertIn(name,paths)

    def test_matrix_keeps_target_and_testnet_separate(self):
        """The Fuzz aggregate requires its independent Network child; E2E/Testnet keeps its own runner."""
        workflow = (ROOT/'.github/workflows/ci.yml').read_text()
        self.assertIn('{"name":"JAM Network","group":"jam-network"}',workflow)
        self.assertIn("if: matrix.family.group == 'jam-network'",workflow)
        self.assertIn('run: make check-jam-network',workflow)
        self.assertIn('jam-network-${{ github.run_attempt }}',workflow)
        self.assertIn('check-jam-network: setup check-inventory',(ROOT/'Makefile').read_text())

    def test_entrypoint_environment_and_exec_status(self):
        """Standard environment-only startup forwards bundled paths exactly and propagates the native process status."""
        with tempfile.TemporaryDirectory() as selected:
            folder = Path(selected); binary = folder/'native'
            binary.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$CAPTURE"\nexit 7\n'); binary.chmod(0o755)
            environment = {key:value for key,value in os.environ.items() if not key.startswith(('JAM_FUZZ','RAGNAROK_FUZZ_'))}
            environment.update(JAM_FUZZ='',JAM_FUZZ_SPEC='fuzz',JAM_FUZZ_DATA_PATH=str(folder/'data'),
                JAM_FUZZ_SOCK_PATH=str(folder/'socket/target.sock'),RAGNAROK_FUZZ_BINARY=str(binary),
                RAGNAROK_FUZZ_CONFIG_DIR=str(ROOT/'config'),CAPTURE=str(folder/'arguments'))
            # Match the pinned upstream launcher's permissive mount directory before container startup.
            (folder/'data').mkdir(mode=0o777); (folder/'data').chmod(0o777)
            (folder/'socket').mkdir(mode=0o777); (folder/'socket').chmod(0o777)
            command = [ROOT/'tools/jam_fuzz_entrypoint.sh']
            result = subprocess.run(command,env=environment,capture_output=True,text=True)
            self.assertEqual(result.returncode,7,result.stderr)
            self.assertEqual((folder/'data').stat().st_mode & 0o777,0o700)
            self.assertEqual((folder/'socket').stat().st_mode & 0o777,0o700)
            arguments = (folder/'arguments').read_text().splitlines()
            self.assertEqual(arguments,['serve-fuzz-preset',str(ROOT/'config/jam-fuzz-policy.conf'),'1000','4194304'])
            (folder/'arguments').unlink()
            for variable in ('JAM_FUZZ','JAM_FUZZ_SPEC','JAM_FUZZ_DATA_PATH','JAM_FUZZ_SOCK_PATH'):
                missing = dict(environment); del missing[variable]
                self.assertNotEqual(subprocess.run(command,env=missing,capture_output=True).returncode,0)
                self.assertFalse((folder/'arguments').exists())
            for value in ('tiny','full','typo'):
                changed = dict(environment,JAM_FUZZ_SPEC=value)
                self.assertNotEqual(subprocess.run(command,env=changed,capture_output=True).returncode,0)
            self.assertNotEqual(subprocess.run(command+['ignored'],env=environment,capture_output=True).returncode,0)
