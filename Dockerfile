# ═══════════════════════════════════════════════════════════════════
# CP2 — Image production cho chat service.
#
# Multi-stage: stage `builder` cài dependency (được phép nặng, sẽ bị vứt đi),
# stage `runtime` chỉ nhận kết quả cài đặt → image nhỏ, không mang theo pip
# cache lẫn công cụ biên dịch.
#
# Build thử:  docker build -t day12-chat:prod .
#             docker images day12-chat:prod
# ═══════════════════════════════════════════════════════════════════

FROM python:3.11-slim AS builder

WORKDIR /app

# requirements.txt copy riêng và cài TRƯỚC source: sửa một dòng code không
# làm Docker huỷ cache của lớp cài thư viện.
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


FROM python:3.11-slim AS runtime

# PYTHONUNBUFFERED để log ra stdout ngay, không nằm trong buffer —
# cloud gom log theo dòng, log bị đệm là log đến muộn.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Chỉ mang KẾT QUẢ cài đặt sang, không mang theo pip cache của stage builder
COPY --from=builder /install /usr/local

COPY app ./app
COPY utils ./utils

# Chạy bằng user thường: thoát được khỏi app cũng không thành root trên host
RUN useradd --create-home --uid 10001 appuser
USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz').read()" || exit 1

# 0.0.0.0 chứ không phải 127.0.0.1 — bind localhost thì ngoài container gọi
# không vào. ${PORT:-8000} vì Railway/Render/Cloud Run tự gán cổng.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
