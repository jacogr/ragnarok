# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Bounded recorded-observation metadata/process tests; native full-map execution is tested separately."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import state_trace_conformance as subject


class RecordedConformance(unittest.TestCase):
    """Unknown profiles, tampering and failed processes cannot become successful external evidence."""

    def setUp(self):
        """Use one synthetic byte bundle for metadata tests only, never as a claimed JAM transition."""
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.identity = dict(graypaper_commit='1'*40,graypaper_version='0.8.0',
                             vectors_commit='2'*40,ark_vrf_version='0.6.0',ark_vrf_commit='3'*40)
        self.parameter = '00'*122
        self.manifest = dict(format=subject.BUNDLE_FORMAT,pins=self.identity,policy='policy',
            reference_sha256='4'*64,transitions=1,cases=[dict(id='case-0000',chain='chain.json',
            genesis='genesis',traces=['step'],parameters=self.parameter,checked=1,final_root='5'*64)],
            files={})
        for name,value in {'policy':b'policy','chain.json':json.dumps(dict(protocol_parameters=self.parameter)).encode(),
                           'genesis':b'genesis','step':b'step'}.items():
            (self.root/name).write_bytes(value)
            self.manifest['files'][name] = hashlib.sha256(value).hexdigest()
        self.profile = dict(format=subject.PROFILE_FORMAT,client=dict(name='controlled test double',
            version='test',artifact_sha256=None),graypaper_commit='1'*40,graypaper_version='0.8.0',
            parameter_profiles=[self.parameter])
        self.write_metadata()
        patcher = patch.object(subject,'pins',return_value=self.identity)
        patcher.start()
        self.addCleanup(patcher.stop)

    def write_metadata(self):
        """Replace synthetic metadata explicitly; no tracked fixtures or observations are touched."""
        (self.root/'manifest.json').write_text(json.dumps(self.manifest))
        (self.root/'profile.json').write_text(json.dumps(self.profile))

    def verify(self):
        """A nonexistent checker/observation directory proves refusals happen before either is accessed."""
        return subject.verify_observations(self.root,self.root/'absent observations',
            self.root/'profile.json',self.root/'absent checker')

    def test_profile_refusals_precede_execution(self):
        """Semver alone and different full tuples never authorize a native/external parity claim."""
        variants = [(None,'0.8.0',[], 'profile-unverified'),
                    ('0'*40,'0.8.0',[self.parameter],'profile-mismatch'),
                    ('1'*40,'0.7.2',[self.parameter],'profile-mismatch'),
                    ('1'*40,'0.8.0',['ff'*122],'profile-mismatch')]
        for commit,version,parameters,wanted in variants:
            self.profile.update(graypaper_commit=commit,graypaper_version=version,parameter_profiles=parameters)
            self.write_metadata()
            with patch.object(subject,'checker_process',side_effect=AssertionError('must not run')):
                report,code = self.verify()
            self.assertEqual((report['status'],code),(wanted,4))
            self.assertFalse(report['external_execution'])
            self.assertEqual(report['cases'],[])

    def test_shapes_paths_and_duplicate_json(self):
        """Malformed/unhashable names, traversal and duplicate JSON fail as typed metadata errors."""
        baseline=copy.deepcopy(self.manifest)
        for value in ([],{},'../outside','/absolute','a/../step','a//b'):
            self.manifest=copy.deepcopy(baseline);self.manifest['cases'][0]['traces']=[value]
            self.write_metadata()
            with self.assertRaises(subject.ConformanceError):
                subject.bundle_manifest(self.root)
        (self.root/'manifest.json').write_text('{"format":1,"format":2}')
        with self.assertRaises(subject.ConformanceError):
            subject.bundle_manifest(self.root)

    def test_payload_tampering_and_profile_binding(self):
        """A changed payload or mismatched declared/native parameter tuple stops before the checker."""
        (self.root/'step').write_bytes(b'changed')
        with self.assertRaisesRegex(subject.ConformanceError,'Artifact identity'):
            self.verify()
        (self.root/'step').write_bytes(b'step')
        changed=json.dumps(dict(protocol_parameters='ff'*122)).encode()
        (self.root/'chain.json').write_bytes(changed)
        self.manifest['files']['chain.json']=hashlib.sha256(changed).hexdigest()
        self.write_metadata()
        with self.assertRaisesRegex(subject.ConformanceError,'parameter tuple'):
            self.verify()

    def test_process_bounds_and_failed_status(self):
        """Controlled local processes exercise both output caps, deadlines and exit preservation."""
        result=subject.checker_process([sys.executable,'-c','print("controlled"); raise SystemExit(7)'],2)
        self.assertEqual((result['exit_code'],result['stdout']),(7,'controlled\n'))
        with self.assertRaisesRegex(subject.ConformanceError,'output limit'):
            subject.checker_process([sys.executable,'-c','print("x"*70000)'],2)
        with self.assertRaisesRegex(subject.ConformanceError,'timed out'):
            subject.checker_process([sys.executable,'-c','import time; time.sleep(10)'],0.1)

    def test_bounded_regular_input(self):
        """Metadata reads refuse oversize files, symlinks and directories without blocking."""
        path=self.root/'input';path.write_bytes(b'ab')
        self.assertEqual(subject.regular_bytes(path,2),b'ab')
        with self.assertRaises(subject.ConformanceError):
            subject.regular_bytes(path,1)
        link=self.root/'link';link.symlink_to(path)
        with self.assertRaises(OSError):
            subject.regular_bytes(link,2)
        with self.assertRaises(subject.ConformanceError):
            subject.regular_bytes(self.root,2)
