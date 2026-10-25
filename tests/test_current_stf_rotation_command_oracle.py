# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent operator file hashes, configured trust, complete-chain selection and refusal progress."""
import hashlib
import json
import unittest
import current_stf_rotation_command_oracle as reference
from state_trace_wire_oracle import prefix


class RotationCommandTests(unittest.TestCase):
    """Only independently authored data supplies expected command results; native output is never imported."""

    @classmethod
    def setUpClass(cls):
        """Retain portable complete input files before inspecting trust/configuration and command outcomes."""
        cls.jobs,cls.expected,cls.evidence=reference.expected_observations()

    def test_complete_host_families_and_exact_final_roots(self):
        """Operator cases retain complete privilege, lifecycle, preimage, transfer, incarnation and offender histories."""
        self.assertEqual((self.evidence['chains'],self.evidence['cases']),(7,13))
        self.assertEqual(self.evidence['transitions'],sum(len(job['steps']) for job in self.jobs[:7]))
        self.assertEqual({family for family,_ in self.evidence['origins']},{'privileges','creation','code','preimages','waves','incarnations','histories'})
        for job,roots,answer in zip(self.jobs[:7],self.evidence['roots'],self.expected[:7]):
            self.assertEqual(answer,'C None '+str(len(job['steps']))+' '+roots[-1])

    def test_complete_parameters_and_genesis_are_trusted_independently(self):
        """Configured header/map and full122-byte parameters agree with authored Genesis, never a supplied trace posterior."""
        for job in self.jobs[:7]:
            config=json.loads(job['config']);parameters=bytes.fromhex(config['protocol_parameters'])
            self.assertEqual(len(parameters),122);self.assertEqual(int.from_bytes(parameters[24:26],'little'),3)
            self.assertEqual(bytes.fromhex(config['genesis_header']),job['genesis'][:297])
            pairs,length=prefix(job['genesis'][297:]);self.assertEqual(length+297,len(job['genesis']))
            self.assertEqual({k.hex():v.hex() for k,v in pairs},config['genesis_state'])
        self.assertEqual(int.from_bytes(bytes.fromhex(json.loads(self.jobs[3]['config'])['protocol_parameters'])[74:78],'little'),0)

    def test_every_portable_file_is_frozen_before_execution(self):
        """Manifest evidence binds exact configuration, Genesis, each trace and expected scalar outcome."""
        for job,metadata,answer in zip(self.jobs,self.evidence['jobs'],self.expected):
            self.assertEqual(metadata['config_sha256'],hashlib.sha256(job['config'].encode()).hexdigest())
            self.assertEqual(metadata['genesis_sha256'],hashlib.sha256(job['genesis']).hexdigest())
            self.assertEqual(metadata['steps_sha256'],[hashlib.sha256(step).hexdigest() for step in job['steps']])
            self.assertEqual(metadata['expected'],answer)

    def test_exact_rejected_bundle_progress_and_no_external_observations(self):
        """Wrong maps/root, trailing bytes and a later bad seal carry exact typed failures and scalar accepted-prefix progress."""
        self.assertEqual(self.evidence['refusals'],['C BootstrapFailure 0 StateMismatch','C TrailingGenesis 0 -',
            'C ImportFailure 0 PostStateMismatch','C TraceFailure 0 TrailingBytes',
            'C ImportFailure 0 PreStateMismatch','C ImportFailure 1 CandidateFailure'])
        self.assertTrue(all('observations' not in job for job in self.jobs))
