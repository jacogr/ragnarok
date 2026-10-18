"""Original signed report/history/known-set projections; no invented parent queue/accumulated chapters."""
from report_policy_fixtures import prepare as policy_prepare

CASES = ('report_curr_rotation-1', 'multiple_reports-1', 'dependency_missing-1',
         'duplicate_package_in_recent_history-1', 'duplicated_package_in_report-1',
         *(f'reports_with_dependencies-{i}' for i in range(1, 7)),
         'segment_root_lookup_invalid-1', 'segment_root_lookup_invalid-2',
         'with_avail_assignments-1', 'many_dependencies-1', 'too_many_dependencies-1')


# Preserve the STF's known_packages union as such; it is not enough to reconstruct C(14)/C(15).
def prepare(folder):
    return policy_prepare(folder, CASES, 'report-packages', include_history=True, include_packages=True)
