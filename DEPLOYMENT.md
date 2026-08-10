# Thông Tin Deploy — Checkpoint 5

> `pytest tests/test_cp5.py` đọc file này để tìm địa chỉ service và gọi thử.
>
> **Chỉ ghi TÊN biến môi trường, tuyệt đối không dán giá trị token vào đây.**
> Repo này công khai — dán token vào là mất token.

## Thông Tin Học Viên

| Mục | Nội dung |
|-----|----------|
| Họ và tên | Nguyễn Đức Anh Tuấn |
| Mã học viên | 2A202601618 |
| Repo | https://github.com/nt15032/K4-DAY12-2A202601618-NguyenDucAnhTuan |

## Service

| Mục | Nội dung |
|-----|----------|
| Public URL | https://k4-day12-2a202601618-nguyenducanhtuan-production.up.railway.app |
| Platform | Railway |
| Ngày deploy | 2026-08-10 |

## Biến Môi Trường Đã Set Trên Cloud

Ghi tên biến và **nguồn giá trị**, không ghi giá trị:

| Biến | Đã set | Ghi chú |
|------|--------|---------|
| `PORT` | ✅ | Railway tự gán, app đọc qua `${PORT:-8000}` |
| `API_TOKEN` | ✅ | đặt trong dashboard Railway, không nằm trong repo |
| `REDIS_URL` | ✅ | Redis add-on của Railway, tự sinh và tham chiếu sang service `chat` |
| `BUCKET_CAPACITY` | ✅ | 10 |
| `REFILL_PER_MINUTE` | ✅ | 10 |
| `DAILY_BUDGET_USD` | ✅ | 1.0 |
| `LOG_LEVEL` | ✅ | INFO |

## Lệnh Kiểm Tra

Thay `<URL>` bằng Public URL ở trên:

```bash
# 1. Liveness — mong đợi 200 {"status":"ok"}
curl -i <URL>/healthz

# 2. Readiness — mong đợi 200 {"status":"ready"} (đã nối được Redis)
curl -i <URL>/readyz

# 3. Không có token — mong đợi 401 kèm header WWW-Authenticate
curl -i -X POST <URL>/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello"}'

# 4. Có token — mong đợi 200 kèm câu trả lời
curl -i -X POST <URL>/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "X-Client-Id: sv-test" \
  -d '{"message":"Deploy là gì?"}'

# 5. Rate limit — gọi 15 lần, những lần cuối phải trả 429
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -X POST <URL>/chat \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "X-Client-Id: sv-test" \
    -d '{"message":"test"}'
done; echo
```

## Kết Quả Chạy Thật

Chạy ngày 2026-08-10 với `URL=https://k4-day12-2a202601618-nguyenducanhtuan-production.up.railway.app`

```
$ curl -i $URL/healthz
HTTP/1.1 200 OK
{"status":"ok","service":"day12-chat-service","version":"1.0.0"}

$ curl -i $URL/readyz
HTTP/1.1 200 OK
{"status":"ready","redis":true}

$ curl -i -X POST $URL/chat -H "Content-Type: application/json" -d '{"message":"Deploy la gi?"}'
HTTP/1.1 401 Unauthorized
www-authenticate: Bearer
{"detail":"invalid or missing bearer token"}

$ curl -X POST $URL/chat -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_TOKEN" -H "X-Client-Id: sv-test" \
    -d '{"message":"Deploy la gi?"}'
{"reply":"Ngắn gọn: Deploy la gi phụ thuộc vào ba yếu tố — cấu hình qua biến môi
trường, health check để orchestrator biết trạng thái, và giới hạn tài nguyên.",
 "client_id":"sv-test","turns_before":0,"usd_cost":2.265e-05,
 "usage":{"prompt":3,"completion":37}}

$ # 15 request liên tiếp, BUCKET_CAPACITY=10 → 10 lần đầu qua, 5 lần sau bị chặn
200 200 200 200 200 200 200 200 200 200 429 429 429 429 429

$ # 3 lượt cùng một client — lịch sử nằm ở Redis nên turns_before tăng dần
turns_before = 0
turns_before = 2
turns_before = 4
```

`pytest tests/test_cp5.py -v` → **9 passed, 4 skipped**.

### Ba lỗi đã gặp khi deploy và cách sửa

| # | Triệu chứng | Nguyên nhân | Cách sửa |
|---|-------------|-------------|----------|
| 1 | `1/1 replicas never became healthy` | đọc nhầm Build Logs, lỗi thật nằm ở Deploy Logs | mở đúng tab Deploy Logs |
| 2 | `Invalid value for '--port': '${PORT:-8000}' is not a valid integer` | Railway chạy `startCommand` **không qua shell** nên cú pháp `${VAR:-default}` của bash tới thẳng uvicorn dạng chuỗi | bỏ `startCommand` khỏi `railway.toml`, để Railway dùng `CMD` của Dockerfile — vốn đã bọc trong `sh -c` |
| 3 | `/readyz` trả 503 `{"redis": false}` | `REDIS_URL` đặt là `redis://localhost:6379/0`; trong container, `localhost` là chính container đó, không phải Redis | tạo Redis add-on và trỏ biến sang `${{Redis.REDIS_URL}}` |

Không lỗi nào trong ba lỗi trên lộ ra khi chạy ở máy — cùng một image chạy hoàn
toàn bình thường bằng `docker compose up -d`.

## Ảnh Chụp Màn Hình

Đặt ảnh trong thư mục `screenshots/`:

- `screenshots/dashboard.png` — trang quản lý service trên platform
- `screenshots/healthz.png` — kết quả gọi `/healthz` từ trình duyệt hoặc curl
