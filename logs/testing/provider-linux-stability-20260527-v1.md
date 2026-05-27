# Log: provider Linux stability 2026-05-27

- Started: 2026-05-27
- Finished: 2026-05-27
- Status: completed
- Plan: plans/running/plan-aihub-provider-linux-stability-20260527-v1.md
- Doc: docs/operations/linux-runtime-notes-20260527-v1.md

## Mục Tiêu
Kiểm tra AI-Q chạy thật sau khi fix setup port AI Hub, job NVIDIA-only và fresh clone từ GitHub.

## Command Chính
- `./setup.sh --up`
- API health/data sources.
- Submit async job và đọc job result/report.
- Fresh clone repo, chạy lại setup và health checks.

## Kết Quả
- Source đã push: `b4cdcde` trên `origin/develop`.
- API/UI chạy trong range `6000-6050`.
- Data sources endpoint hoạt động.
- Job shallow NVIDIA-only hoàn tất và trả report thật.

## Lỗi Linux Hay Gặp
- `egg-info` bị regenerate khi bootstrap Python, làm working tree bẩn.
- Port cũ ngoài `6000-6050` xung đột với Hub hoặc Docker Desktop.
- Process dev server còn chạy nền nếu setup không detach/stop đúng.
- Thiếu optional Tavily/Serper không được biến thành fallback ảo khi test NVIDIA-only.

## Rủi Ro Còn Lại
- Full sources mode cần Tavily và Serper key thật để kiểm thử web/paper search end-to-end.
