# Plan: aihub-provider-linux-stability

- Created: 2026-05-27 00:00
- Updated: 2026-05-27 23:40
- Status: completed
- Related log: logs/testing/provider-linux-stability-20260527-v1.md
- Related doc: docs/operations/linux-runtime-notes-20260527-v1.md

## Goal
Ổn định AI-Q khi AI Hub clone lại repo provider, chạy thật hosted NVIDIA và dùng host port trong range `6000-6050`.

## Scope
- In: setup API/UI, data source endpoints, job shallow research bằng NVIDIA, fresh clone install.
- Out: không yêu cầu Tavily/Serper nếu đang kiểm thử NVIDIA-only, không commit `.env` thật, không push folder evidence tổng.

## Skills
- testing-skill
- plan-skill
- logging-skill
- documentation-skill
- push-code-skill

## Phases
| Phase | Goal | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Rà setup Linux và port | done | README, setup output |
| 2 | Fix port `6000-6050` và job NVIDIA-only | done | commit `b4cdcde` |
| 3 | Test local và fresh clone | done | health, data sources, job report |
| 4 | Push source provider | done | `origin/develop` tại `b4cdcde` |

## Verification
- `./setup.sh --up`
- API health, UI load, data source list.
- Submit job shallow với NVIDIA-only và xác nhận report hoàn tất.
- Fresh clone từ GitHub sau push.

## Close Criteria
- Source clone lại chạy được trong range `6000-6050`.
- Output job thật có nội dung từ hosted NVIDIA, không dùng mock/fallback.
- Không lưu secret vào repo.
