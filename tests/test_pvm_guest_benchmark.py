# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect the grouped real-guest pack's provenance, family identity and atomic measurements."""
from copy import deepcopy
import csv
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from dependencies import ROOT
import pvm_guest_benchmark as pack
from pvm_sieve_benchmark import verify_fixture
from pvm_sieve_report import limits_for_guest, parse_process_output, summarize
from test_pvm_sieve import output, report


def child(guest):
    """Complete deterministic reports carry the same family on every structured pass."""
    result = report(guest)
    result['guest'] = guest
    for row in result['passes']:
        row['guest'] = guest
    return result


def refresh_descriptor(folder, name):
    """Permit semantic-negative metadata tests to reach validation beyond member digests."""
    path = folder/'pvm_guests.fixture.json'
    data = json.loads(path.read_text())
    data['files']['pvm-guests/'+name] = hashlib.sha256((folder/'pvm-guests'/name).read_bytes()).hexdigest()
    path.write_text(json.dumps(data, sort_keys=True))


class GuestPackTests(unittest.TestCase):
    """All coherent workloads must complete all controls before any aggregate table is valid."""

    def test_frozen_sources_and_dependencies(self):
        """All frozen artifacts and guest/host locks use the existing upstream source and package identities."""
        expected = {'minimal': 'dc14d67a05a7f34cb606e9e5cc19d7758259f44ae91e1e4c046fc72852f59a86',
                    'memset': '7f65561fbcbec23b6ea1a991013875782fad7e9a3d97262e8ef41451d5b80f10',
                    'pinky': '9976f59732625268d8eb2dc3d159932176af4f898bdc0c3b07ad0079ef2f7d09'}
        for guest, digest in expected.items():
            observed = verify_fixture(upstream=ROOT/'vendor/polkavm', guest=guest)
            self.assertEqual(observed['artifact_sha256'], digest)
            self.assertEqual(observed['guest_toolchain'], 'nightly-2025-05-10')
            self.assertEqual(observed['instruction_set'], 'JamV1')
        with self.assertRaises(ValueError):
            verify_fixture(guest='foreign')

    def test_pinky_members_and_family_are_bound(self):
        """A separate NES descriptor rejects every changed/missing member and coordinated family relabeling."""
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            shutil.copytree(ROOT/'tests/fixtures/pvm-pinky',folder/'pvm-pinky')
            descriptor=folder/'pvm_pinky.fixture.json'
            shutil.copy(ROOT/'tests/fixtures/pvm_pinky.fixture.json',descriptor)
            for path in sorted((folder/'pvm-pinky').iterdir()):
                original=path.read_bytes()
                try:
                    # License, ROM attribution, lock and generated artifact are all mandatory identities.
                    path.write_bytes(original+b'!')
                    with self.subTest(member=path.name),self.assertRaises(ValueError):
                        verify_fixture(folder,guest='pinky')
                    path.unlink()
                    with self.assertRaises(FileNotFoundError):verify_fixture(folder,guest='pinky')
                finally:
                    path.write_bytes(original)
            path=folder/'pvm-pinky/pinky.provenance.json'
            data=json.loads(path.read_text());data['guest']='minimal'
            path.write_text(json.dumps(data))
            metadata=json.loads(descriptor.read_text())
            metadata['files']['pvm-pinky/pinky.provenance.json']=hashlib.sha256(path.read_bytes()).hexdigest()
            descriptor.write_text(json.dumps(metadata))
            with self.assertRaisesRegex(ValueError,'family mismatch'):
                verify_fixture(folder,upstream=ROOT/'vendor/polkavm',guest='pinky')

    def test_every_pack_member_is_mandatory(self):
        """Missing or changed entries, manifests, artifacts, licenses and metadata fail either selection."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            shutil.copytree(ROOT/'tests/fixtures/pvm-guests', folder/'pvm-guests')
            shutil.copy(ROOT/'tests/fixtures/pvm_guests.fixture.json', folder)
            for path in sorted((folder/'pvm-guests').iterdir()):
                original = path.read_bytes()
                try:
                    path.write_bytes(original+b'!')
                    for guest in ('minimal','memset'):
                        with self.subTest(member=path.name, guest=guest), self.assertRaises(ValueError):
                            verify_fixture(folder, guest=guest)
                    path.unlink()
                    with self.assertRaises(FileNotFoundError):
                        verify_fixture(folder, guest='minimal')
                finally:
                    path.write_bytes(original)

    def test_semantic_provenance_is_not_just_member_hashes(self):
        """Coordinated metadata/checksum edits still cannot substitute another family or source prefix."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            shutil.copytree(ROOT/'tests/fixtures/pvm-guests', folder/'pvm-guests')
            shutil.copy(ROOT/'tests/fixtures/pvm_guests.fixture.json', folder)
            for guest in ('minimal','memset'):
                path = folder/'pvm-guests'/(guest+'.provenance.json')
                original = path.read_text()
                data = json.loads(original)
                if guest == 'minimal':
                    # A different valid family cannot take the selected artifact's identity.
                    data['guest'] = 'memset'
                else:
                    # A full-source digest does not certify an altered extracted algorithm boundary.
                    data['upstream_prefix']['bytes'] += 1
                path.write_text(json.dumps(data))
                refresh_descriptor(folder, path.name)
                with self.subTest(guest=guest), self.assertRaises(ValueError):
                    verify_fixture(folder, upstream=ROOT/'vendor/polkavm', guest=guest)
                path.write_text(original)
                refresh_descriptor(folder, path.name)

    def test_guest_lock_cannot_add_unpinned_package(self):
        """Updating matching member/provenance digests cannot authorize a dependency version upgrade."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            shutil.copytree(ROOT/'tests/fixtures/pvm-guests', folder/'pvm-guests')
            shutil.copy(ROOT/'tests/fixtures/pvm_guests.fixture.json', folder)
            lock = folder/'pvm-guests/guest-Cargo.lock'
            text = lock.read_text()
            original = 'name = "picoalloc"\nversion = "5.0.0"'
            self.assertIn(original, text)
            lock.write_text(text.replace(original, 'name = "picoalloc"\nversion = "5.0.1"', 1))
            refresh_descriptor(folder, lock.name)
            digest = hashlib.sha256(lock.read_bytes()).hexdigest()
            for guest in ('minimal','memset'):
                path = folder/'pvm-guests'/(guest+'.provenance.json')
                data = json.loads(path.read_text())
                data['guest_lock_sha256'] = digest
                path.write_text(json.dumps(data))
                refresh_descriptor(folder, path.name)
                with self.assertRaisesRegex(ValueError, 'Unpinned guest dependency'):
                    verify_fixture(folder, upstream=ROOT/'vendor/polkavm', guest=guest)

    def test_family_prefix_and_structured_identity(self):
        """A complete sample pass must retain its exact family through raw parsing and summary rendering."""
        for guest in pack.GUESTS:
            limit=limits_for_guest(guest)[0]
            for engine in ('ragnarok', 'polkavm_interpreter'):
                valid = 'GUEST,'+guest+'\n'+output(engine,limit)
                self.assertEqual(parse_process_output(valid, engine, limit, guest)['guest'], guest)
                for bad in (output(engine,limit), valid.replace('GUEST,'+guest, 'GUEST,sieve', 1),
                            'GUEST,'+guest+'\n'+valid):
                    with self.subTest(guest=guest, engine=engine), self.assertRaises(ValueError):
                        parse_process_output(bad, engine, limit, guest)
                with self.assertRaises(ValueError):
                    parse_process_output(valid, engine, limit)
            structured = child(guest)
            self.assertIn('interpreter comparison', summarize(structured))
            structured['passes'][0]['guest'] = 'sieve'
            with self.assertRaises(ValueError):
                summarize(structured)
        with self.assertRaises(ValueError):
            parse_process_output(output(), 'ragnarok', 1000, 'foreign')

    def test_pack_requires_every_complete_family(self):
        """Missing, repeated, foreign or failed children never generate a successful aggregate table."""
        complete = dict(status='checks-passed', guests=[child(guest) for guest in pack.GUESTS])
        self.assertIn('Indirect calls interpreter comparison', pack.summarize_pack(complete))
        self.assertIn('Memory fill interpreter comparison', pack.summarize_pack(complete))
        for rows in (complete['guests'][:1], complete['guests'][:-1], complete['guests']*2,
                     [complete['guests'][0]]*2, list(reversed(complete['guests']))):
            with self.assertRaises(ValueError):
                pack.summarize_pack(dict(status='checks-passed', guests=rows))
        broken = deepcopy(complete)
        broken['guests'][1]['status'] = 'failed'
        with self.assertRaises(ValueError):
            pack.summarize_pack(broken)

    def test_success_retains_all_samples_and_warmups(self):
        """Aggregate output preserves all 520 raw observations and their explicit family identity."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)

            def measured(*, guest, build):
                """Stand in for the separately verified native processes without running a benchmark in unit tests."""
                observed = json.loads((folder/'results.json').read_text())
                self.assertEqual(observed['status'], 'running')
                self.assertEqual(len(observed['guests']), pack.GUESTS.index(guest))
                build.mkdir()
                (build/'results.json').write_text(json.dumps(child(guest)))

            with patch.object(pack, 'BUILD', folder), patch.object(pack, 'run_guest', measured), patch('builtins.print'):
                pack.run()
            with (folder/'samples.csv').open() as source:
                rows = list(csv.DictReader(source))
            self.assertEqual(len(rows), 520)
            self.assertEqual({row['guest'] for row in rows}, set(pack.GUESTS))
            self.assertEqual(sum(row['warmup'] == 'True' for row in rows), 120)
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'], 'checks-passed')

    def test_failed_second_guest_retires_previous_success(self):
        """A partial pack failure clears stale aggregate downloads and suppresses successful tables."""
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            for name in ('samples.csv', 'summary.md', 'results.json'):
                (folder/name).write_text('stale success')

            def measured(*, guest, build):
                """Retain one real-shaped child before a deterministic second-family failure."""
                self.assertEqual(json.loads((folder/'results.json').read_text())['status'], 'running')
                if guest == 'memset':
                    raise ValueError('second guest failed')
                observed = json.loads((folder/'results.json').read_text())
                self.assertEqual(observed['status'], 'running')
                self.assertEqual(len(observed['guests']), pack.GUESTS.index(guest))
                build.mkdir()
                (build/'results.json').write_text(json.dumps(child(guest)))

            with patch.object(pack, 'BUILD', folder), patch.object(pack, 'run_guest', measured):
                with self.assertRaisesRegex(ValueError, 'second guest failed'):
                    pack.run()
            self.assertFalse((folder/'samples.csv').exists())
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'], 'failed')
            self.assertNotIn('| Limit |', (folder/'summary.md').read_text())

    def test_failed_pinky_cannot_publish_the_earlier_two_guests(self):
        """A final-family failure must retire old downloads even after minimal and memory fill succeed."""
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            for name in ('samples.csv','summary.md','results.json'):
                (folder/name).write_text('stale success')
            def measured(*,guest,build):
                """Keep real-shaped earlier evidence and fail only the newly added final family."""
                if guest=='pinky':raise ValueError('Pinky failed')
                build.mkdir();(build/'results.json').write_text(json.dumps(child(guest)))
            with patch.object(pack,'BUILD',folder),patch.object(pack,'run_guest',measured):
                with self.assertRaisesRegex(ValueError,'Pinky failed'):pack.run()
            result=json.loads((folder/'results.json').read_text())
            self.assertEqual(result['status'],'failed')
            self.assertEqual([row['guest'] for row in result['guests']],['minimal','memset'])
            self.assertFalse((folder/'samples.csv').exists())
            self.assertNotIn('| Limit |',(folder/'summary.md').read_text())

    def test_opt_in_make_scope(self):
        """Normal setup provisions interpreter hosts only; full correctness does not acquire benchmark work."""
        make = (ROOT/'Makefile').read_text()
        target = make.split('bench-pvm-guests: setup\n', 1)[1].split('\n\n', 1)[0]
        self.assertIn('cargo fetch --locked', target)
        self.assertIn('tools/pvm_guest_benchmark.py', target)
        self.assertNotIn('nightly-2025', target)
        self.assertNotIn('bench-pvm-guests', make.split('check: ', 1)[1].splitlines()[0])
