# AI-Q Blueprint: Giải thích ngắn gọn theo phạm vi file đang push

Tài liệu này chỉ mô tả các thành phần nằm trong danh sách nên push hiện tại:
- `setup.sh`
- `aiq-explanation.md`
- `pyproject.toml`
- `uv.lock`
- `src/`
- `frontends/aiq_api/`
- `frontends/ui/`
- `sources/knowledge_layer/`
- `sources/tavily_web_search/`
- `sources/google_scholar_paper_search/`
- `configs/config_web_default_llamaindex.yml`
- `deploy/compose/docker-compose.yaml`
- `deploy/.env.example`

## 1) Bóc tách và tùy biến source code

## 1.1 Cấu trúc kỹ thuật trong phạm vi hiện tại

1. Lõi workflow/agent
- Vị trí: `src/`
- Vai trò: điều phối intent, shallow/deep research, tổng hợp kết quả và citation.

2. API backend cho web
- Vị trí: `frontends/aiq_api/`
- Vai trò: cung cấp endpoint web/API, async jobs, stream tiến độ.

3. Frontend web
- Vị trí: `frontends/ui/`
- Vai trò: UI chat, chọn nguồn dữ liệu, hiển thị plan/report/citations.

4. Nguồn dữ liệu mặc định
- Vị trí: `sources/tavily_web_search/`, `sources/google_scholar_paper_search/`, `sources/knowledge_layer/`
- Vai trò:
  - Tavily cho web search.
  - Google Scholar/Serper cho paper search.
  - Knowledge layer cho upload/retrieval tài liệu.

5. Cấu hình runtime chính
- Vị trí: `configs/config_web_default_llamaindex.yml`
- Vai trò: định nghĩa llm, tools, data source registry, workflow cho web mode mặc định.

6. Vận hành và triển khai
- Vị trí: `setup.sh`, `deploy/compose/docker-compose.yaml`, `deploy/.env.example`
- Vai trò:
  - `setup.sh`: lifecycle `--up/--down/--clean`.
  - Compose: support service postgres.
  - `.env.example`: mẫu biến môi trường.

## 1.2 Điểm tùy biến quan trọng

1. Tùy biến model/tool/workflow:
- Chỉnh trong `configs/config_web_default_llamaindex.yml`.

2. Tùy biến hành vi runtime:
- Dùng biến môi trường mà `setup.sh` hỗ trợ:
  - `AIQ_BACKEND_PORT`
  - `AIQ_FRONTEND_PORT`
  - `AIQ_POSTGRES_PORT`
  - `AIQ_CONFIG_FILE`
  - `AIQ_SUPPORT_SERVICES`
  - `AIQ_REQUIRE_FULL_SOURCES`

3. Tùy biến data source:
- Chỉnh tool/data source tương ứng trong:
  - `sources/tavily_web_search/`
  - `sources/google_scholar_paper_search/`
  - `sources/knowledge_layer/`

## 2) Khởi động hệ thống

## 2.1 Chuẩn bị

1. Tạo file env từ mẫu:

```bash
cp deploy/.env.example deploy/.env
```

2. Điền key cần thiết trong `deploy/.env`:
- `NVIDIA_API_KEY`
- `TAVILY_API_KEY`
- `SERPER_API_KEY`

## 2.2 Chạy hệ thống

```bash
./setup.sh --up
```

`--up` sẽ:
1. Nạp env và kiểm tra key bắt buộc.
2. Khởi động postgres qua `deploy/compose/docker-compose.yaml` (nếu bật support services).
3. Bootstrap hoặc tái sử dụng môi trường phụ thuộc.
4. Tự xử lý xung đột cổng backend/frontend/postgres.
5. Khởi động backend + frontend.
6. Ghi `.runtime/ports.env` để lưu cổng thực tế.

## 2.3 Dừng và dọn

1. Dừng dịch vụ:

```bash
./setup.sh --down
```

2. Dọn sạch artifacts cục bộ:

```bash
./setup.sh --clean
```

## 3) Sử dụng frontend UI

1. Chạy `./setup.sh --up`.
2. Lấy URL frontend/backend từ output.
3. Mở URL frontend để chat.
4. Chọn nguồn dữ liệu theo registry trong `configs/config_web_default_llamaindex.yml`.
5. (Tùy chọn) upload tài liệu để dùng qua knowledge layer.

Mẹo:
- Nếu cổng mặc định bị chiếm, luôn dùng URL mới in ra từ `setup.sh`.

## 4) Xem logs

Khi chạy bằng `setup.sh`, theo dõi:
- `.runtime/backend.log`
- `.runtime/frontend.log`
- `.runtime/ports.env`

Lệnh xem nhanh:

```bash
tail -f .runtime/backend.log
tail -f .runtime/frontend.log
```

Health check backend (dùng cổng thực tế):

```bash
curl http://localhost:<BACKEND_PORT>/health
```

## 5) Cách lõi hoạt động

1. Câu hỏi đi vào agent workflow trong `src/` để phân loại intent.
2. Hệ thống chọn đường shallow hoặc deep research.
3. Agent gọi tool qua registry trong `configs/config_web_default_llamaindex.yml`.
4. Web search/paper search/knowledge retrieval được thực thi qua các source package đã push.
5. API ở `frontends/aiq_api/` stream tiến độ và trả kết quả cho UI ở `frontends/ui/`.
6. Runtime do `setup.sh` quản lý, có tự phục hồi cổng và quản lý vòng đời dịch vụ.

---

## Phụ lục: Checklist trước khi push

1. Có đủ các mục trong danh sách push ở đầu tài liệu.
2. Không đưa thêm thành phần ngoài phạm vi cần chạy flow hiện tại.
3. Đảm bảo `setup.sh` chạy được với `--up`, `--down`, `--clean`.