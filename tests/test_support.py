"""Shared repository identity and process-workload peer selection; assertions live in Nim."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


# Networking workloads use the one Nim peer and its one-thread dispatcher baseline.
def networking_peers(build, skip_build, thread_baselines, variant=None):
    assert (build/'nim-peer').is_file(), 'Build the native peer before running this workload'
    thread_baselines['nim'] = 1
    return ('nim',)
