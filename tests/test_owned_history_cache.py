# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent derivation caching must preserve caller ownership and never retain a failed attempt."""
import unittest
from owned_history_cache import owned_histories


class OwnedHistoryCacheTests(unittest.TestCase):
    """Use explicit fresh fake histories without consulting native execution or real protocol state."""

    def test_nested_maps_steps_events_and_inventory_are_owned(self):
        """Mutating all nested caller data cannot change either a concurrent or later caller's expected histories."""
        calls=[]
        @owned_histories
        def derive():
            """Return a small complete mutable history shape and record actual derivation calls."""
            calls.append(1)
            return [dict(initial={b'k':b'v'},steps=[(b'b',{b'k':b'n'},[])],events=[dict(gas=[0])],inventory_rows=[[42,[],[]]])]
        a=derive();b=derive();a[0]['initial'][b'k']=b'changed';a[0]['steps'][0][1][b'k']=b'changed'
        a[0]['events'][0]['gas'].append(7);a[0]['inventory_rows'][0][1].append(b'x');a[0]['steps'].clear()
        self.assertEqual(derive(),b);self.assertEqual(calls,[1])

    def test_failed_derivation_is_not_cached(self):
        """An assertion or fixture failure must not become a successful empty/stale expected history."""
        calls=[]
        @owned_histories
        def derive():
            """Fail once before producing any complete expected data; only the later successful call can be retained."""
            calls.append(1)
            if len(calls)==1:raise ValueError('incomplete independent derivation')
            return [{b'k':b'v'}]
        with self.assertRaisesRegex(ValueError,'incomplete independent derivation'):derive()
        self.assertEqual(derive(),[{b'k':b'v'}]);self.assertEqual(derive(),[{b'k':b'v'}]);self.assertEqual(len(calls),2)


if __name__=='__main__':
    unittest.main()
