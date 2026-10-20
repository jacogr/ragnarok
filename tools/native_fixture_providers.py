# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Register generated-fixture callables with source-owned ordering, inputs and evidence metadata.

Exposes FixtureProviders and PROVIDERS. Suite requirements own consumer/variant selection;
registration never prepares data or imports the requirements being validated.
"""
from dataclasses import dataclass
from functools import wraps
import re
import sys


# Keep execution metadata immutable while looking up callables live for isolated harness substitution.
@dataclass(frozen=True)
class FixtureProvider:
    """One callable's preparation group, order, resources, variants and historical report identity."""
    name: str
    module: str
    function: str
    group: str
    order: int
    inputs: tuple
    variants: tuple
    evidence: tuple | None
    deferred: bool

    # The declaring module owns the callable; no central function-name dispatch table is needed.
    def prepare(self, folder, **context):
        """Invoke only this provider's declared inputs; reject absent required resources."""
        if any(context.get(key) is None for key in self.inputs):
            raise ValueError('Missing native fixture provider input: '+self.name)
        function = getattr(sys.modules[self.module], self.function)
        return function(folder, **{key: context[key] for key in self.inputs})


# Providers register at their definitions; metadata validation makes discovery fail before preparation.
class FixtureProviders:
    """Own callable declarations and derive deterministic plans without a provider-name list."""
    def __init__(self):
        """Create an empty, isolated set of declarations without invoking providers."""
        self.providers = {}

    # Declare execution contracts locally; aggregate callables already return suite-bound manifests.
    def fixture(self, *, group, order, inputs=(), variants=('default',), evidence=None,
                deferred=False, aggregate=False):
        """Register a named fixture callable and bind its variants to declared consumers at runtime."""
        if (group not in ('root', 'sealer', 'runtime') or type(order) is not int or order < 1
                or not isinstance(inputs, tuple)
                or any(not isinstance(key, str) or key not in ('certificates', 'integration') for key in inputs)
                or len(inputs) != len(set(inputs))
                or bool(inputs) != (group == 'runtime') or type(deferred) is not bool
                or type(aggregate) is not bool or (deferred and group != 'root')):
            raise ValueError('Invalid native fixture provider execution metadata')
        if (not isinstance(variants, tuple) or not variants
                or any(not isinstance(key, str) or re.fullmatch(r'[a-z][a-z0-9_]*', key) is None
                       for key in variants) or len(variants) != len(set(variants))
                or (aggregate and group != 'root')):
            raise ValueError('Invalid native fixture provider variants')
        if group == 'root':
            # Only top-level preparation stages publish separate evidence files; nested stages retain their schema.
            if (not isinstance(evidence, tuple) or len(evidence) != 2
                    or any(not isinstance(value, str) or re.fullmatch(r'[a-z][a-z0-9_-]*', value) is None
                           for value in evidence)):
                raise ValueError('Invalid native fixture provider evidence')
        elif evidence is not None:
            raise ValueError('Unexpected nested native fixture provider evidence')

        # Derive the provider identity from its callable rather than maintaining a second list of names.
        def register(function):
            match = re.fullmatch(r'unit_([a-z][a-z0-9_]*)_fixture', function.__name__)
            if match is None or match[1] in self.providers:
                raise ValueError('Invalid or duplicate native fixture provider: '+function.__name__)
            for provider in self.providers.values():
                # Execution ranks and output identities are unique within their respective scopes.
                if (provider.group, provider.order) == (group, order):
                    raise ValueError('Duplicate native fixture provider order')
                if evidence and provider.evidence and any(a == b for a, b in zip(evidence, provider.evidence)):
                    raise ValueError('Duplicate native fixture provider evidence')
            name = match[1]
            provider = FixtureProvider(name, function.__module__, function.__name__, group, order,
                                       inputs, () if aggregate else variants, evidence, deferred)
            self.providers[name] = provider
            if aggregate:
                # The nested aggregate explicitly owns its report shape rather than pretending to be a variant.
                return function

            # Raw providers return variants; consumers are derived only from their own requirements files.
            @wraps(function)
            def prepare(*args, **kwargs):
                values, observed = function(*args, **kwargs)
                if not isinstance(values, dict) or set(values) != set(provider.variants):
                    raise ValueError('Invalid native fixture provider result: '+name)
                from native_requirements import NATIVE_REQUIREMENTS
                fixtures = {suite: values[record.get('variant', 'default')]
                            for suite, record in NATIVE_REQUIREMENTS.items()
                            if record.get('provider') == name}
                return fixtures, observed
            return prepare
        return register

    # Preserve the original pipeline order while allowing each provider to own its placement.
    def plan(self, group):
        """Return the declared group ordered by its explicit execution ranks."""
        return sorted((provider for provider in self.providers.values() if provider.group == group),
                      key=lambda provider: provider.order)

    # The standalone launcher derives generated evidence filenames from the same provider declarations.
    def evidence_files(self):
        """Return report-key-to-filename mappings without a separate generated-stage registry."""
        return {provider.evidence[0]: provider.evidence[1]
                for provider in self.providers.values() if provider.evidence}


# Importing the declaring native_fixtures module populates this instance without preparing any data.
PROVIDERS = FixtureProviders()
