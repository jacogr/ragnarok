#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run the owning RPC workload with real-browser assertions against the production peer build.

Exposes a focused Make entry point, reusing certificate generation, peer cleanup and RPC checks.
"""
import json
import sys
from toolchain_archives import ROOT
sys.path.insert(0, str(ROOT/'tests'))
from test_quic import fixtures
from rpc_checks import run


# Independent focused runs retain their own TLS identities and browser evidence under build/.
def main():
    folder = ROOT/'build/tests/ui-browser'
    folder.mkdir(parents=True, exist_ok=True)
    certificates = fixtures(folder/'certificates')
    chain = folder/'chain.json'
    chain.write_bytes((ROOT/'tests/fixtures/rpc-genesis.json').read_bytes())
    result = run(ROOT/'build/ragnarok', certificates, folder/'peer', chain=chain, ui=True, browser=True)
    (folder/'results.json').write_text(json.dumps(result, indent=2)+'\n')
    assert result['passed']
    print('PASS Nimony browser prototype with production ragnarok_clientInfo')


if __name__ == '__main__':
    main()
