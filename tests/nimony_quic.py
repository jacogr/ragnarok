"""Prepare the unchanged pinned LSQUIC/TLS library and ignored fixture identities for Nimony."""
from test_quic import BUILD, PINS, dependencies, build_native, fixtures


# Build only the native bridge; this trial never invokes the historical Nim 2 peer entry point.
def prepare():
    library = build_native(dependencies(False))
    fixture_folder = BUILD/'nimony-fixtures'
    fixtures(fixture_folder)
    return library, fixture_folder, dict(pins=PINS, patches=[], build_log='build/quic/build.log')
