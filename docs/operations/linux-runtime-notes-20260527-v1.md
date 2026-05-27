# Linux Runtime Notes: AI-Q

- Date: 2026-05-27
- Status: completed
- Related plan: ../../plans/running/plan-aihub-provider-linux-stability-20260527-v1.md
- Related log: ../../logs/testing/provider-linux-stability-20260527-v1.md

## Port Rule
AI Hub installs must use host ports in `6000-6050`. Current verified defaults are API `6042`, UI `6043`, internal Next dev `6044` and Postgres `6045` when available.

## Common Linux Issues
- Python package metadata under `*.egg-info` can change during editable installs; do not commit generated noise unless package metadata intentionally changed.
- Stop old API/UI processes before reinstalling.
- Use hosted NVIDIA mode on AMD/Windows/Linux without local NVIDIA runtime.
- If Tavily/Serper are absent, verify NVIDIA-only jobs explicitly instead of claiming full web/paper search.

## Verified Output
Evidence was captured locally under `test/provider-fix-evidence-2026-05-27/aiq/` in the Hub workspace. It includes UI, health, data sources, job status and job report screenshots for local and fresh clone runs.
