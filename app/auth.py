"""CP3 — Xác thực bằng Bearer token.

Public URL = ai cũng gọi được. Không có lớp này, hóa đơn LLM của bạn do
người lạ quyết định.

Chuẩn dùng ở đây là **RFC 6750** — token đi trong header ``Authorization``:

    Authorization: Bearer <token>

Đây là cách mọi API lớn (GitHub, Stripe, OpenAI) nhận token, nên client viết
bằng ngôn ngữ nào cũng có sẵn thư viện hiểu nó.
"""

from __future__ import annotations

import secrets

from fastapi import Header, HTTPException, status

from .config import get_settings

ANONYMOUS_CLIENT = "anonymous"
SCHEME = "Bearer"


def verify_bearer_token(
    authorization: str | None = Header(default=None),
    x_client_id: str | None = Header(default=None),
) -> str:
    """Kiểm tra header ``Authorization``; trả về client_id nếu hợp lệ.

    client_id trả về là đơn vị để rate limit và tính chi phí.
    """
    # Cùng một lỗi cho mọi trường hợp: nói rõ "sai scheme" hay "sai token"
    # là tặng thông tin cho người đang dò. WWW-Authenticate là bắt buộc
    # theo chuẩn HTTP — nó cho client biết phải xác thực kiểu gì.
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="invalid or missing bearer token",
        headers={"WWW-Authenticate": SCHEME},
    )

    if not authorization:
        raise unauthorized

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != SCHEME.lower() or not token:
        raise unauthorized

    # compare_digest chứ không phải ==: toán tử == dừng ngay tại ký tự đầu
    # khác nhau, nên thời gian trả lời rò rỉ token ra từng ký tự một.
    if not secrets.compare_digest(token, get_settings().api_token):
        raise unauthorized

    return x_client_id or ANONYMOUS_CLIENT
