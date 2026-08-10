# Phiếu Phản Ánh — K4 Ngày 12

> **Bài làm cá nhân.** Các câu dưới đây trả lời dựa trên những gì quan sát được
> khi tự chạy code: số đo image, log thật của container, mã trạng thái thu được
> khi gọi API, và log lỗi thật lúc deploy lên Railway.
>
> Họ và tên: Nguyễn Đức Anh Tuấn   Mã học viên: 2A202601618

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `api_token` không có giá trị mặc định nên app chết ngay khi
khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà việc
"chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Tình huống: tôi deploy lên Railway và quên set `API_TOKEN` trong tab Variables.

Với mặc định `"changeme"`, app khởi động bình thường, `/healthz` trả 200,
healthcheck của Railway xanh, dashboard báo Success. Nhìn mọi thứ đều ổn nên
tôi đóng tab và chuyển sang việc khác. Nhưng URL là công khai, và `"changeme"`
nằm trong mọi wordlist mà bot quét Internet dùng. Bot tìm ra endpoint mới trong
vài giờ, thử token mặc định, vào được, rồi gọi `/chat` thoải mái bằng ngân sách
của tôi. Tôi chỉ phát hiện khi nhìn hóa đơn cuối tháng — tức là sau khi tiền đã
mất, và lúc đó tôi còn phải truy ngược log để hiểu chuyện gì xảy ra.

Không có mặc định thì `Settings()` ném `ValidationError` ngay lúc process khởi
động, container thoát, healthcheck fail, deployment bị đánh dấu đỏ. Tôi thấy
lỗi **trong lúc còn đang nhìn màn hình deploy**, sửa mất 30 giây. Tôi đã quan
sát đúng cơ chế này ở CP2: khi `shutdown_guard.arm()` còn là stub và ném
`NotImplementedError`, container exit code 3 ngay lập tức và
`docker compose ps` báo `exited` — lỗi không có chỗ nào để ẩn.

Điểm mấu chốt: giá trị mặc định biến "lỗi cấu hình" thành "lỗ hổng bảo mật im
lặng". Không mặc định thì nó chỉ là "deploy fail", ồn ào và vô hại.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/chat` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Dòng log thật lấy từ `docker compose logs chat`:

```json
{"event": "chat_completed", "severity": "INFO", "ts": "2026-08-10T08:16:22.563420+00:00", "client_id": "sv-burst", "prompt_tokens": 335, "completion_tokens": 52, "usd_cost": 8.145e-05}
```

**Việc 1 — Tổng hợp theo trường để trả lời câu hỏi về tiền.** Vì `client_id` và
`usd_cost` là hai trường riêng biệt có kiểu dữ liệu rõ ràng, tôi hỏi được
"client nào tiêu nhiều nhất hôm nay" bằng một truy vấn nhóm theo `client_id` và
cộng `usd_cost`. Với `print("đã trả lời xong")` thì không có số nào để cộng;
kể cả khi in ra `print(f"client {cid} tốn {cost}")` thì vẫn phải viết regex để
bóc số ra khỏi câu văn, và regex đó vỡ ngay khi có người sửa câu chữ hoặc khi
`client_id` chứa dấu cách.

**Việc 2 — Cảnh báo tự động theo mức độ.** Khóa `severity` viết hoa là quy ước
Google Cloud Logging đọc được, nên tôi đặt được luật "khi tỷ lệ dòng có
`severity` là `ERROR` vượt 5% trong 5 phút thì gửi cảnh báo". `print()` không
có khái niệm mức độ — mọi dòng đều là stdout như nhau, hệ thống giám sát không
phân biệt được dòng nào là sự cố, nên cách duy nhất còn lại là con người ngồi
đọc log bằng mắt.

Điểm chung của cả hai: log JSON là *dữ liệu có cấu trúc*, còn `print()` là *văn
xuôi cho người đọc*. Máy không đọc văn xuôi đáng tin cậy được.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

Tôi build lại bản một stage (đúng nội dung Dockerfile gốc: `FROM python:3.11`,
`COPY . .`, `RUN pip install`) rồi so với bản multi-stage:

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | **1730 MB** (1.73 GB) |
| Multi-stage | **270 MB** |

Chênh lệch **1.46 GB**, tức bản multi-stage chỉ bằng khoảng 1/6.

Phần chênh lệch đó gồm ba nhóm:

1. **Base image.** `python:3.11` bản đầy đủ nặng khoảng 1 GB vì mang theo cả
   toolchain build (gcc, make, các header của thư viện hệ thống), tài liệu,
   và nhiều công cụ dev. `python:3.11-slim` bỏ hết những thứ đó, còn khoảng
   130 MB. Riêng đổi base image đã chiếm phần lớn khoản chênh.
2. **Rác của quá trình cài đặt.** Bản một stage chạy `pip install` ngay trong
   image cuối, nên toàn bộ cache của pip và các file tạm nằm lại trong layer.
   Bản multi-stage cài ở stage `builder` với `--no-cache-dir --prefix=/install`,
   rồi stage runtime chỉ `COPY --from=builder /install /usr/local` — chỉ lấy
   kết quả, không lấy quá trình. Stage `builder` bị vứt đi hoàn toàn.
3. **File không cần thiết trong context.** `COPY . .` mang cả `.git`, `tests/`,
   `screenshots/`, `.venv` nếu có, và tệ nhất là `.env` — tức là secret bị
   nướng thẳng vào image rồi đẩy lên registry. Bản mới chỉ `COPY app ./app` và
   `COPY utils ./utils`, cộng thêm `.dockerignore` chặn sẵn.

Điều đáng nói là ý 3 không chỉ là chuyện dung lượng: nó là chuyện lộ secret.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Tôi thêm một dòng comment vào cuối `app/main.py` rồi chạy
`docker build --progress=plain`. Kết quả thật:

| Layer | Trạng thái |
|-------|-----------|
| `[builder 2/4] WORKDIR /app` | CACHED |
| `[builder 3/4] COPY requirements.txt .` | CACHED |
| `[builder 4/4] RUN pip install --no-cache-dir --prefix=/install -r requirements.txt` | **CACHED** |
| `[runtime 3/6] COPY --from=builder /install /usr/local` | CACHED |
| `[runtime 4/6] COPY app ./app` | chạy lại |
| `[runtime 5/6] COPY utils ./utils` | chạy lại |
| `[runtime 6/6] RUN useradd --create-home --uid 10001 appuser` | chạy lại |

Layer đắt nhất — cài 30 gói từ mạng — được dùng lại nguyên vẹn, nên build lần
hai xong trong khoảng 20 giây thay vì vài phút.

Lý do: Docker băm nội dung đầu vào của từng layer để quyết định cache. Nó duyệt
từ trên xuống, giữ cache tới layer đầu tiên có đầu vào thay đổi, rồi **huỷ cache
của layer đó và tất cả layer sau nó**. `requirements.txt` không đổi nên
`pip install` giữ được cache; `app/` đổi nên `COPY app ./app` và mọi thứ phía
sau phải chạy lại. Ba layer cuối chạy lại đều rẻ (copy vài chục KB và tạo một
user), nên tổng chi phí gần như bằng không.

Nếu đặt `COPY . .` trước `RUN pip install` thì mọi thứ đảo ngược: `COPY . .` là
layer sớm, mà chỉ cần sửa **một ký tự trong bất kỳ file nào** của repo là đầu
vào của nó đổi. Cache huỷ từ đó trở đi, kéo theo `pip install` — tức là mỗi lần
sửa một dấu phẩy trong code, Docker tải và cài lại toàn bộ 30 thư viện từ đầu.
Vòng lặp sửa-build-thử từ 20 giây thành vài phút, và trên CI thì nhân lên theo
mỗi commit.

Quy tắc rút ra: **xếp layer theo tần suất thay đổi, ít đổi nhất lên trên.**
Dependency đổi vài tuần một lần nên nằm trên; code đổi vài phút một lần nên nằm
dưới cùng.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

Chuỗi sự kiện:

1. **Có lỗ hổng cho phép chạy lệnh.** Ví dụ một endpoint nhận input người dùng
   rồi đưa vào `subprocess`, `eval`, hoặc deserialize dữ liệu không tin cậy.
   Kẻ tấn công gửi payload và chạy được lệnh tùy ý *bên trong container*.
2. **Lệnh đó chạy với uid 0.** Vì `Dockerfile` không có `USER`, tiến trình
   uvicorn là root, nên lệnh vừa chèn cũng là root trong container.
3. **Root trong container gần như là root trên host.** Docker mặc định không
   bật user namespace remapping, nên uid 0 trong container *chính là* uid 0
   trên host ở tầng kernel. Chúng chia sẻ cùng một kernel.
4. **Kẻ tấn công mở rộng quyền.** Với uid 0 hắn: đọc/ghi mọi bind mount được
   gắn vào container (nếu ai đó mount `/var/run/docker.sock` thì coi như xong
   ngay — điều khiển được toàn bộ Docker daemon); dùng các capability còn lại
   như `CAP_DAC_OVERRIDE`, `CAP_SETUID`; hoặc khai thác một lỗ hổng escape của
   runtime/kernel — và các lỗ hổng loại này hầu như đều yêu cầu *phải là root
   trong container* mới khai thác được.
5. **Kết quả:** một lỗi ở tầng ứng dụng Python trở thành quyền root trên máy
   chủ, kéo theo mọi container khác đang chạy trên cùng host đó.

`USER appuser` cắt chuỗi ở **bước 2–3**. Tiến trình chạy với uid 10001, nên:
lệnh chèn vào ở bước 1 vẫn chạy nhưng chỉ với quyền của một user thường; không
ghi được vào `/usr`, `/etc` hay bất cứ thứ gì thuộc hệ thống; không có
capability đặc quyền nào; và tuyệt đại đa số kỹ thuật thoát container ở bước 4
đơn giản là không dùng được. Lỗ hổng vẫn là lỗ hổng, nhưng thiệt hại bị giam
trong phạm vi của một tiến trình không đặc quyền thay vì lan ra cả host.

Đây là nguyên tắc **defence in depth**: ta không giả định code của mình không
bao giờ có lỗ hổng, ta chỉ đảm bảo rằng khi có lỗ hổng thì nó không đủ sức leo
thang.

---

### Câu 6 — Bearer token (CP3)

Vì sao 401 phải kèm header `WWW-Authenticate: Bearer`? Và vì sao ta trả **cùng
một** thông báo lỗi cho cả ba trường hợp (thiếu header, sai scheme, sai token)
thay vì nói rõ sai ở đâu cho người dùng dễ sửa?

**Về `WWW-Authenticate`:** chuẩn HTTP (RFC 7235) quy định response 401 *bắt
buộc* phải kèm header này. Lý do là 401 chỉ nói "bạn chưa được xác thực" — nó
không nói *phải xác thực bằng cách nào*. Header này trả lời câu đó: scheme cần
dùng là `Bearer`, không phải `Basic`, `Digest` hay OAuth flow nào khác. Nhờ vậy
client tự động — thư viện HTTP, trình duyệt, công cụ sinh SDK — biết phải làm
gì tiếp mà không cần đọc tài liệu của riêng API này. Thiếu nó thì response về
mặt kỹ thuật là sai chuẩn, và client chỉ biết mình bị từ chối chứ không biết
đường sửa. Tôi kiểm tra được điều này trên bản deploy thật:

```
$ curl -i -X POST $URL/chat -H "Content-Type: application/json" -d '{"message":"Deploy la gi?"}'
HTTP/1.1 401 Unauthorized
www-authenticate: Bearer
{"detail":"invalid or missing bearer token"}
```

**Về việc dùng chung một thông báo:** ba trường hợp đó tách ra thì tạo thành
một *oracle* — một cỗ máy trả lời đúng/sai từng phần cho người đang dò. Nếu tôi
trả "sai scheme" thì kẻ tấn công biết ngay endpoint này dùng Bearer và hắn chỉ
còn phải đoán token. Nếu tôi trả "token không đúng" thì hắn biết scheme đã
chuẩn, header đã đúng chỗ, và thứ duy nhất còn thiếu là giá trị token — tức là
hắn đã thu hẹp không gian tìm kiếm mà không tốn công gì. Mỗi mẩu thông tin ấy
đều rút ngắn thời gian dò.

Trả cùng một câu cho cả ba trường hợp nghĩa là phản hồi của server không mang
thông tin nào giúp người dò tiến gần hơn tới đáp án. Người dùng hợp lệ thì
không bị ảnh hưởng: họ có token đúng và tài liệu API, họ không cần server đoán
hộ mình sai ở đâu.

Cùng logic đó là lý do dùng `secrets.compare_digest` thay vì `==`: `==` dừng ở
ký tự đầu tiên khác nhau nên *thời gian phản hồi* cũng là một kênh rò rỉ, đoán
đúng càng nhiều ký tự đầu thì trả lời càng chậm. `compare_digest` luôn chạy hết
chuỗi nên thời gian không nói lên điều gì.

---

### Câu 7 — Token bucket (CP3)

Với `capacity=10`, `refill_per_minute=10`: một client im lặng 10 phút rồi gửi
liên tiếp. Nó gửi được bao nhiêu request trước khi bị 429? Nếu bỏ đoạn
`min(capacity, ...)` trong `available()` thì con số đó thành bao nhiêu, và tại sao?

**Có `min(capacity, ...)`: gửi được đúng 10 request, request thứ 11 bị 429.**

Im lặng 10 phút thì lượng token nhỏ thêm là `600 giây × (10/60) = 100 token`,
nhưng `min(float(self.capacity), tokens)` chặn trên ở 10. Xô đầy tối đa là 10,
không hơn. Trong lúc bắn liên tiếp thì thời gian trôi qua không đáng kể nên
lượng nạp thêm gần bằng 0. Sau 10 lần `consume`, `tokens` còn 0, lần thứ 11
rơi vào nhánh `tokens < 1` và nhận 429 kèm `Retry-After`.

Tôi đo trên bản deploy Railway với `BUCKET_CAPACITY=10`, gửi 15 request liên
tiếp cùng một `X-Client-Id`:

```
200 200 200 200 200 200 200 200 200 200 429 429 429 429 429
```

Đúng 10 lần đầu qua, 5 lần sau bị chặn.

**Bỏ `min(...)`: thành khoảng 100 request.**

Không có chặn trên thì `tokens` cộng dồn tuyến tính theo thời gian im lặng:
`0 + 600 × 0.1667 ≈ 100`. Client im lặng 10 phút bắn được 100 phát liên tiếp;
im lặng một ngày thì `86400 × 0.1667 = 14.400` token và bắn được 14.400 phát
trong vài giây.

Điều này phá hỏng đúng mục đích của rate limit. Ý nghĩa của `capacity` là "mức
bùng phát tối đa mà hệ thống chịu được trong một khoảnh khắc" — nó là thứ bảo
vệ ta khỏi việc 14.400 request đập vào cùng lúc làm sập service hoặc đốt sạch
ngân sách trong vài giây. Còn `refill_per_minute` là "tốc độ trung bình cho
phép về lâu dài". Thiếu `min(...)` thì ta chỉ còn giới hạn tốc độ trung bình mà
mất hoàn toàn giới hạn bùng phát, và tốc độ trung bình không cứu nổi một hệ
thống đang bị dội 14.400 request trong một giây.

---

### Câu 8 — Ngân sách theo ngày (CP3)

So sánh hạn mức $30/tháng với hạn mức $1/ngày cho cùng một client. Giả sử có sự
cố khiến một client gọi liên tục từ 2h sáng. Với mỗi cách, thiệt hại tối đa là
bao nhiêu và service tự hồi phục khi nào?

Hai cách có cùng "tổng ngân sách" nhưng hành vi khi có sự cố khác nhau hoàn toàn.

| | $30/tháng | $1/ngày |
|---|---|---|
| Thiệt hại tối đa của một sự cố | **$30** — toàn bộ ngân sách tháng | **$1** |
| Sự cố lúc 2h sáng bị chặn khi nào | khi đã tiêu hết $30 | khi đã tiêu hết $1 trong ngày đó |
| Service hồi phục lúc nào | **đầu tháng sau** — có thể tới 30 ngày | **00:00 UTC hôm sau**, tự động |
| Cần người can thiệp không | Có | Không |

**Với hạn mức tháng:** client lỗi gọi liên tục từ 2h sáng, không có gì chặn cho
tới khi chạm mốc $30. Nếu sự cố xảy ra ngày mùng 3 thì $30 bay trong một đêm, và
27 ngày còn lại của tháng client đó **không dùng được dịch vụ nữa** — mà đây là
client hợp lệ, chỉ là code của họ có bug. Muốn khôi phục thì phải có người thức
dậy, phát hiện ra, và nâng hạn mức bằng tay. Tệ hơn nữa: hạn mức tháng chỉ báo
động *sau khi* phần lớn tiền đã mất, nên nó gần như vô dụng với vai trò cảnh báo
sớm.

**Với hạn mức ngày:** cũng sự cố đó, `check()` chặn khi `spent()` vượt $1 —
thường chỉ sau vài phút. Thiệt hại dừng ở $1, tức 1/30 so với cách kia. Đến
00:00 UTC, key `spend:<client>:<YYYY-MM-DD>` đổi sang ngày mới, `spent()` trả
0.0, service tự phục vụ lại **mà không cần ai chạm vào**. Sáng ra tôi thấy log
và đi sửa nguyên nhân, chứ không phải đi chữa cháy.

Nói cách khác: hạn mức ngày biến "sự cố ngân sách" từ một sự kiện cần trực đêm
thành một dòng log để đọc vào sáng hôm sau. Đó là lý do nó đáng giá hơn hạn mức
tháng dù con số tổng có thể như nhau.

Cũng cần nhớ rate limit và cost guard không thay thế nhau: 10 request/phút nghe
an toàn, nhưng nếu mỗi request tiêu 50.000 token thì ngân sách vẫn bay trong
vài phút. Một cái giới hạn *số lượng*, cái kia giới hạn *số tiền*.

---

### Câu 9 — /healthz khác /readyz (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

Giả sử cả 3 container dùng chung một endpoint `/healthz` có gọi `store.ping()`,
và orchestrator dùng nó làm liveness probe.

1. **Giây 0** — Redis mất kết nối (restart để vá lỗi, đổi node, hoặc mạng chớp).
2. **Giây 0–5** — probe định kỳ chạy trên cả 3 container. `store.ping()` trả
   `False` ở cả ba, nên cả ba cùng trả 503. Điểm chí mạng: chúng hỏng **đồng
   thời**, vì chúng phụ thuộc cùng một thứ.
3. **Giây ~5–15** — orchestrator đọc 503 từ *liveness* probe. Ngữ nghĩa của
   liveness là "process này hỏng, cần restart", nên nó **giết và khởi động lại
   cả 3 container cùng lúc**. Ngay lúc này số instance phục vụ được tụt xuống 0.
4. **Giây ~15–30** — container mới khởi động, probe chạy lại, Redis vẫn chưa
   lên → lại 503 → lại bị restart. Vòng lặp restart (Kubernetes gọi là
   `CrashLoopBackOff`), và mỗi lần lặp thì backoff dài thêm.
5. **Giây 30** — Redis sống lại. Nhưng lúc này **không còn container nào đang
   chạy** để phục vụ: chúng hoặc đang khởi động dở, hoặc đang nằm chờ hết thời
   gian backoff.
6. **Giây 30 → 60+** — các container lần lượt khởi động lại, warm-up, mở kết
   nối. Downtime thật kéo dài **lâu hơn nhiều** so với 30 giây sự cố ban đầu.

Kết quả: một sự cố dependency 30 giây bị khuếch đại thành downtime toàn hệ
thống vài phút, và tự ta gây ra bằng chính cơ chế lẽ ra để bảo vệ mình.

Tách hai endpoint thì kịch bản khác hẳn. `/readyz` (có kiểm tra Redis) trả 503
→ load balancer **ngừng gửi request mới** vào các instance đó nhưng **không
restart** chúng. `/healthz` (không chạm dependency) vẫn trả 200 vì process vẫn
sống khoẻ. Container đứng yên chờ. Giây 30 Redis quay lại, `ping()` trả `True`,
`/readyz` trả 200 ngay ở nhịp probe kế tiếp, load balancer đẩy traffic vào lại.
Tổng downtime xấp xỉ đúng 30 giây của sự cố gốc, không cộng thêm gì.

Khác biệt nằm ở chỗ hai câu hỏi này khác nhau về bản chất: *"process này có cần
restart không?"* và *"instance này có nên nhận traffic lúc này không?"*. Restart
một container vì Redis chết không sửa được gì cả — Redis vẫn chết, mà giờ ta mất
thêm cả container.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

Tôi gặp ba lỗi nối tiếp nhau khi deploy lên Railway. Lỗi đáng nhớ nhất là lỗi
thứ hai.

**Thông báo lỗi.** Ban đầu tôi chỉ thấy trong Build Logs:

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

Gọi vào URL thì nhận 404 kèm header `x-railway-fallback: true` và body
`{"status":"error","code":404,"message":"Application not found"}` — tức là edge
proxy của Railway trả lời thay vì app, vì phía sau không có replica nào sống.

**Cách tìm ra nguyên nhân.** Build Logs không có gì bất thường: image build
thành công, push xong. Sai lầm của tôi là cứ đọc mãi Build Logs. Nguyên nhân
nằm ở **Deploy Logs** — một tab khác hẳn, ghi những gì xảy ra *sau khi* image
đã chạy. Mở đúng tab đó thì thấy ngay, lặp lại mỗi giây:

```
Usage: uvicorn [OPTIONS] APP
Error: Invalid value for '--port': '${PORT:-8000}' is not a valid integer.
```

Tôi cũng đối chiếu với bản chạy ở máy: cùng image đó, `docker compose up -d`
cho container `healthy`, `/healthz` trả 200, `/readyz` trả `{"status":"ready",
"redis":true}`. Chạy đúng ở local mà hỏng trên cloud ⇒ vấn đề không nằm trong
code mà nằm ở cách môi trường gọi nó.

**Nguyên nhân.** Tôi để `startCommand` trong `railway.toml` dùng cú pháp
`--port ${PORT:-8000}`. Cú pháp `${VAR:-default}` là *parameter expansion của
shell*, chỉ có nghĩa khi có shell diễn giải nó. Railway chạy `startCommand`
trực tiếp chứ không qua shell, nên chuỗi `${PORT:-8000}` tới thẳng uvicorn dưới
dạng văn bản thô và uvicorn từ chối vì nó không phải số nguyên.

**Cách sửa.** Bỏ hẳn `startCommand` khỏi `railway.toml` để Railway dùng `CMD`
của Dockerfile:

```dockerfile
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
```

`CMD` này gọi tường minh qua `sh -c`, nên biến được expand đúng — đó cũng chính
là lý do nó luôn chạy ổn ở local. Sau khi sửa, `/healthz` trả 200 ngay.

**Hai lỗi còn lại**, ghi lại cho đủ:

| Lỗi | Nguyên nhân | Cách sửa |
|-----|-------------|----------|
| `/readyz` trả 503 `{"redis": false}` | tôi đặt `REDIS_URL=redis://localhost:6379/0` trên cloud. Trong container, `localhost` là chính container đó chứ không phải Redis | tạo Redis add-on rồi trỏ biến sang `${{Redis.REDIS_URL}}` |
| dùng nhầm một API key của Gemini làm `API_TOKEN` | tưởng `API_TOKEN` là key mua từ nhà cung cấp LLM | `API_TOKEN` là secret **do mình tự đặt** để bảo vệ `/chat`; lab dùng mock LLM offline nên không cần key của ai cả |

**Bài học chung của cả ba.** Không lỗi nào lộ ra khi chạy ở máy — cùng một
image, cùng một `docker compose up -d`, mọi thứ xanh. Chúng chỉ xuất hiện khi
môi trường thật khác đi: lệnh khởi động được gọi theo cách khác, `localhost`
trỏ tới thứ khác, biến môi trường do người khác điền. Đó chính là lý do 12-Factor
bắt tách config ra khỏi code, và cũng là lý do phải deploy thật ít nhất một lần
thay vì tin rằng "chạy được ở máy tôi là xong".
