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

Trạng thái lúc ghi file này: bản deploy trên Railway **chưa lên được** — healthcheck
thất bại 3 lần liên tiếp nên không có replica nào phục vụ, edge proxy của Railway
trả 404 thay cho app:

```
$ curl -i https://k4-day12-2a202601618-nguyenducanhtuan-production.up.railway.app/healthz
HTTP/1.1 404 Not Found
Server: railway-hikari
x-railway-fallback: true

{"status":"error","code":404,"message":"Application not found"}
```

Log build phía Railway:

```
====================
Starting Healthcheck
====================
Path: /healthz
Retry window: 30s

Attempt #1 failed with service unavailable. Continuing to retry for 19s
Attempt #2 failed with service unavailable. Continuing to retry for 8s
1/1 replicas never became healthy!
Healthcheck failed!
```

Cùng image đó chạy ở máy bằng `docker compose up -d` thì hoàn toàn bình thường —
nên đây là lỗi cấu hình môi trường trên cloud, không phải lỗi code:

```
$ docker compose ps
chat   running  Up 16 seconds (healthy)
redis  running  Up 10 minutes (healthy)

$ curl -s http://localhost:8000/healthz
{"status":"ok","service":"day12-chat-service","version":"1.0.0"}

$ curl -s http://localhost:8000/readyz
{"status":"ready","redis":true}

$ curl -i -X POST http://localhost:8000/chat -H "Content-Type: application/json" -d '{"message":"Hi"}'
HTTP/1.1 401 Unauthorized
www-authenticate: Bearer

$ # 3 request liên tiếp cùng client — lịch sử nằm ở Redis nên turns_before tăng dần
turns_before = 0 | usd_cost = 2.505e-05 | usage = {'prompt': 3, 'completion': 41}
turns_before = 2 | usd_cost = 3.84e-05  | usage = {'prompt': 48, 'completion': 52}
turns_before = 4 | usd_cost = 4.665e-05 | usage = {'prompt': 103, 'completion': 52}

$ # 15 request liên tiếp với BUCKET_CAPACITY=10
200 200 200 200 200 200 200 200 200 200 429 429 429 429 429
```

## Ảnh Chụp Màn Hình

Đặt ảnh trong thư mục `screenshots/`:

- `screenshots/dashboard.png` — trang quản lý service trên platform
- `screenshots/healthz.png` — kết quả gọi `/healthz` từ trình duyệt hoặc curl
