# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Freeze source sets, native dependency closure and artifacts before any successful benchmark report."""
from contextlib import contextmanager
import hashlib
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import storage_benchmark as benchmark


@contextmanager
def inputs():
    """Use isolated real files for every hashed boundary; subprocess substitution supplies only Git/Clang metadata."""
    with tempfile.TemporaryDirectory() as temporary:
        folder=Path(temporary);build=folder/'build';(build/'growth/io').mkdir(parents=True)
        files={name:folder/name for name in ('source.nim','compiler','bridge','loader','provider','native')}
        files.update(growth=build/'growth/growth-native',observed=build/'growth/io/growth-io-native',
            observer=build/'growth/io/storage-io-observer.o')
        for name,path in files.items():
            path.write_bytes(b'provider' if name in ('loader','provider') else name.encode())
        digest=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
        components=dict(bridge=files['bridge'],provider_loader=files['loader'],provider_build=files['provider'])
        sources=[files['source.nim']]
        state=dict(head='a'*40,dirty=b'',clang='fixture clang')
        report=dict(head=state['head'],worktree_dirty=False,clang=state['clang'],sources={'source.nim':digest(files['source.nim'])},
            compiler_sha256=digest(files['compiler']),native_components={k:digest(v) for k,v in components.items()},
            native_binary_sha256=digest(files['native']),growth=dict(native_binary_sha256=digest(files['growth']),
                io=dict(native_binary_sha256=digest(files['observed']),observer_object_sha256=digest(files['observer']))))
        def metadata(arguments,**kwargs):
            if arguments[:2]==['git','rev-parse']: return state['head']+'\n'
            if arguments[:2]==['git','status']: return state['dirty']
            if arguments==['clang','--version']: return state['clang']+'\n'
            raise AssertionError(arguments)
        with patch.object(benchmark,'ROOT',folder),patch.object(benchmark,'BUILD',build),patch.object(
                benchmark,'benchmark_sources',return_value=sources),patch.object(benchmark,'crypto_components',return_value=components),patch.object(
                benchmark.subprocess,'check_output',side_effect=metadata):
            yield files,state,report,lambda:benchmark.verify_inputs(report,files['compiler'],files['bridge'],files['native']),sources


class StorageBenchmarkInputTests(unittest.TestCase):
    """Successful earlier samples cannot hide a changed input or mixed native provider at publication time."""

    def test_identical_content_survives_timestamp_change(self):
        with inputs() as (files,state,report,verify,sources):
            verify()
            os.utime(files['source.nim'],ns=(1000000000,1000000000))
            verify()

    def test_every_native_and_source_boundary_is_frozen(self):
        for name in ('source.nim','compiler','bridge','loader','provider','native','growth','observed','observer'):
            with self.subTest(name=name),inputs() as (files,state,report,verify,sources):
                files[name].write_bytes(b'changed input')
                with self.assertRaises(RuntimeError):
                    verify()

    def test_added_and_removed_source_inputs_refuse(self):
        with inputs() as (files,state,report,verify,sources):
            extra=files['source.nim'].parent/'new.nim';extra.write_bytes(b'new input');sources.append(extra)
            with self.assertRaisesRegex(RuntimeError,'sources'):
                verify()
        with inputs() as (files,state,report,verify,sources):
            files['source.nim'].unlink()
            with self.assertRaises(OSError):
                verify()

    def test_head_dirty_state_and_clang_identity_are_frozen(self):
        for field,value in (('head','b'*40),('dirty',b' M source.nim'),('clang','different clang')):
            with self.subTest(field=field),inputs() as (files,state,report,verify,sources):
                state[field]=value
                with self.assertRaisesRegex(RuntimeError,'input changed'):
                    verify()

    def test_missing_provider_cannot_be_ignored(self):
        with inputs() as (files,state,report,verify,sources):
            files['loader'].unlink()
            with self.assertRaises(OSError):
                verify()


if __name__=='__main__':
    unittest.main()
