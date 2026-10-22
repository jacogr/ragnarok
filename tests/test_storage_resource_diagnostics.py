# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Resource diagnostics preserve unavailable stages and use only matching within-process observations."""
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import storage_lifetime_benchmark as lifetime
import storage_deployment_benchmark as deployment
from storage_resource_diagnostics import lifetime_rows, deployment_growth, summarize
from storage_resource_panel_fixtures import fixture


class StorageResourceDiagnosticTests(unittest.TestCase):
    """Simple independently authored counters make the intended arithmetic observable."""

    def test_live_allocator_baselines_and_unavailable_stages(self):
        """An absent owner stays unavailable, while a closed owner has a measured zero live increment."""
        rows = lifetime_rows(fixture(lifetime))
        initial = next(r for r in rows if r['scenario']=='fixture' and r['items']==8192)
        self.assertIsNone(initial['owner_net_bytes'])
        owner = next(r for r in rows if r['scenario']=='owner' and r['items']==8192)
        self.assertEqual(owner['owner_net_bytes'],800)
        self.assertEqual(owner['closed_net_bytes'],0)
        copied = next(r for r in rows if r['scenario']=='extraction' and r['items']==8192)
        self.assertEqual(copied['closed_net_bytes'],400)

    def test_growth_requires_matching_backend_order_and_publications(self):
        """No absent64-publication baseline is invented; independently constant occupancy normalizes by extent."""
        report = fixture(deployment); rows = deployment_growth(report)
        self.assertEqual(len(rows),18)
        value = next(r for r in rows if r['backend']=='memory' and r['items']==131072 and r['pass_index']==0)
        self.assertEqual(value['normalized_growth'],0.25)
        self.assertIn('Process peak RSS is never subtracted',summarize(fixture(lifetime),report))
