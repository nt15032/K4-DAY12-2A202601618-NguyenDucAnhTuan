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
| Public URL | https://day12-chat-nsgq.onrender.com |
| Platform | Render (Blueprint đọc `render.yaml`) |
| Ngày deploy | 2026-08-10 |

## Biến Môi Trường Đã Set Trên Cloud

Ghi tên biến và **nguồn giá trị**, không ghi giá trị:

| Biến | Đã set | Ghi chú |
|------|--------|---------|
| `PORT` | ✅ | Render tự gán (10000); app đọc qua `${PORT:-8000}` trong `CMD` |
| `API_TOKEN` | ✅ | khai báo `sync: false` trong `render.yaml` → Render hỏi lúc tạo Blueprint, không nằm trong repo |
| `REDIS_URL` | ✅ | `fromService` trỏ tới Key Value `day12-chat-redis`, Render tự nối |
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
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Client-Id: sv-test" \
  -d '{"message":"Deploy là gì?"}'

# 5. Rate limit — gọi 15 lần, những lần cuối phải trả 429
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -X POST <URL>/chat \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-Client-Id: sv-test" \
    -d '{"message":"test"}'
done; echo
```

## Kết Quả Chạy Thật

Chạy ngày 2026-08-10 với `URL=https://day12-chat-nsgq.onrender.com`

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
    -H "Authorization: Bearer $TOKEN" -H "X-Client-Id: sv-test" \
    -d '{"message":"Deploy la gi?"}'
{"reply":"Ngắn gọn: Deploy la gi phụ thuộc vào ba yếu tố — cấu hình qua biến môi
trường, health check để orchestrator biết trạng thái, và giới hạn tài nguyên.
(Mình đang nhớ 2 lượt trao đổi trước đó.)","client_id":"sv-test",
 "turns_before":2,"usd_cost":3.465e-05,"usage":{"prompt":43,"completion":47}}

$ # 15 request liên tiếp, BUCKET_CAPACITY=10
200 200 200 200 200 200 200 200 200 200 429 429 429 200 429

$ # 3 lượt cùng một client — lịch sử nằm ở Key Value nên turns_before tăng dần
turns_before = 0
turns_before = 2
turns_before = 4
```

Chú ý cái `200` xen giữa các `429` ở lần thứ 14: đó **không phải lỗi** mà là token
bucket đang nạp lại. Mỗi vòng gọi Render mất khoảng 1,5 giây nên 15 request kéo
dài chừng 25 giây, đủ để xô nhỏ thêm vài token (`REFILL_PER_MINUTE=10` tương
đương 1 token mỗi 6 giây). Đây chính là điểm khác giữa token bucket và cách
"tối đa N request mỗi phút": xô hồi phục dần theo thời gian chứ không reset theo
mốc.

`pytest tests/test_cp5.py -v` → **9 passed, 4 skipped**.

### Các lỗi đã gặp khi deploy và cách sửa

Bài này được deploy thử trên cả hai nền tảng. Bảng dưới ghi lại toàn bộ lỗi thật.

| # | Nền tảng | Triệu chứng | Nguyên nhân | Cách sửa |
|---|----------|-------------|-------------|----------|
| 1 | Railway | `1/1 replicas never became healthy` | đọc nhầm Build Logs; lỗi thật nằm ở Deploy Logs | mở đúng tab Deploy Logs |
| 2 | Railway | `Invalid value for '--port': '${PORT:-8000}' is not a valid integer` | Railway chạy `startCommand` **không qua shell** nên cú pháp `${VAR:-default}` của bash tới thẳng uvicorn dạng chuỗi | bỏ `startCommand` khỏi `railway.toml`, để dùng `CMD` của Dockerfile — vốn đã bọc trong `sh -c` |
| 3 | Railway | `/readyz` trả 503 `{"redis": false}` | đặt `REDIS_URL=redis://localhost:6379/0`; trong container, `localhost` là chính container đó | trỏ biến sang `${{Redis.REDIS_URL}}` |
| 4 | Render | `/healthz` lúc 200 lúc 404 kèm `x-render-routing: no-server` (8/12 thành công) | `HEALTHCHECK` trong Dockerfile cắm cứng cổng 8000 trong khi `CMD` đọc `$PORT`, mà Render gán `PORT=10000` | sửa `HEALTHCHECK` đọc `os.environ.get('PORT', '8000')`; sau đó đo lại được 12/12 |
| 5 | Render | `day12-chat.onrender.com` trả `/healthz` 200 nhưng `/chat` từ chối token | subdomain là tài nguyên **toàn cục**, tên `day12-chat` đã bị học viên khác chiếm; Render cấp cho mình `day12-chat-nsgq` | lấy URL từ dashboard thay vì đoán, và xác minh chủ sở hữu bằng token riêng |

Lỗi số 4 đáng chú ý nhất: nó nằm trong code từ CP2 nhưng Railway không làm lộ ra,
vì Railway gán `PORT=8000` — trùng đúng con số bị cắm cứng. Đổi nền tảng mới thấy.

Lỗi số 5 cho một bài học riêng: `/healthz` trả 200 **không chứng minh** đó là
service của mình. Thứ chứng minh được là secret chỉ mình có.

### Hạn chế của free tier Render

Render tự tắt instance khi không có traffic khoảng 15 phút; request kế tiếp mất
tới 50 giây để đánh thức. `test_cp5.py` vẫn qua vì `test_healthz_tra_ve_200` có
timeout 60 giây và chạy đầu tiên — nó đánh thức service cho các test sau. Nhưng
nếu mở URL bằng trình duyệt sau một lúc không dùng thì lần tải đầu sẽ rất chậm.

## Luồng CI/CD

Deploy không còn làm bằng tay. Mỗi lần push lên `main`:

```
git push
   ↓
GitHub Actions ── job test  (pytest trên máy sạch) ──┐
               └─ job build (docker build + kiểm tra <400MB) ──┤
                                                               │ cả hai xanh
                                                               ▼
                                            job deploy: gọi Render Deploy Hook
                                                               ▼
                                                  Render build và deploy
                                                               ▼
                                     smoke test: curl /healthz, thử lại tối đa 10 lần
```

Hai thứ khiến đây là một cổng chất lượng chứ không chỉ là tự động hoá:

- `needs: [test, build]` — job deploy không khởi động nếu test hoặc build đỏ
- **Auto-Deploy của service Render đã tắt** — nếu để bật, Render sẽ tự bắt commit
  và deploy ngay lúc push, song song với test, nên code hỏng vẫn lên được
  production trong khi Actions còn đang đỏ. Tắt nó thì đường deploy duy nhất đi
  qua Deploy Hook, và hook chỉ được gọi sau khi mọi thứ xanh.

Deploy Hook nằm trong GitHub Secrets với tên `RENDER_DEPLOY_HOOK`, không nằm
trong repo. Khi được gọi, Render trả về id của deployment vừa tạo — đó là cách
xác nhận hook thật sự chạy chứ không chỉ trả 200 suông.

## Ảnh Chụp Màn Hình

Đặt ảnh trong thư mục `screenshots/`:

- `screenshots/dashboard.png` — trang quản lý service trên platform
- `screenshots/healthz.png` — kết quả gọi `/healthz` từ trình duyệt hoặc curl
