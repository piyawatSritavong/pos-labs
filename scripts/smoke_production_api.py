#!/usr/bin/env python3
"""Production API smoke test with reversible fixtures.

Required:
  POS_API_ADMIN_PASSWORD=... python3 scripts/smoke_production_api.py

Optional:
  POS_API_BASE_URL=https://pos-labs.onrender.com
  POS_API_ADMIN_USERNAME=admin
  POS_API_REPORT_DIR=reports
"""

from __future__ import annotations

import base64
import datetime as dt
import hashlib
import json
import os
import secrets
import socket
import ssl
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


BASE_URL = os.getenv("POS_API_BASE_URL", "https://pos-labs.onrender.com").rstrip("/")
ADMIN_USERNAME = os.getenv("POS_API_ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.getenv("POS_API_ADMIN_PASSWORD", "")
REPORT_DIR = Path(os.getenv("POS_API_REPORT_DIR", "reports"))
ROUTE_MANIFEST = Path(__file__).with_name("api_routes.txt")
RUN_ID = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S")
FAKE_ID = f"SMOKE-NOT-FOUND-{RUN_ID}"

results: list[dict[str, Any]] = []
cleanup_actions: list[tuple[str, str, str, Any, str | None]] = []
admin_token = ""
pos_secret = ""


def redact(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            key: ("<redacted>" if "token" in key.lower() or "secret" in key.lower() or key.lower() == "password" else redact(val))
            for key, val in value.items()
        }
    if isinstance(value, list):
        return [redact(item) for item in value[:10]]
    return value


def decode_body(body: bytes, content_type: str) -> Any:
    if "json" in content_type:
        try:
            return json.loads(body)
        except json.JSONDecodeError:
            return body.decode("utf-8", "replace")[:500]
    if content_type.startswith("text/") or "csv" in content_type:
        return body.decode("utf-8", "replace")[:500]
    return f"<binary {len(body)} bytes sha256={hashlib.sha256(body).hexdigest()[:16]}>"


def request(
    method: str,
    path: str,
    *,
    token: str | None = None,
    json_body: Any = None,
    raw_body: bytes | None = None,
    content_type: str | None = None,
    timeout: int = 60,
) -> tuple[int, dict[str, str], bytes, float]:
    headers = {"Accept": "application/json", "User-Agent": "posdemo-production-smoke/1.0"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = raw_body
    if json_body is not None:
        data = json.dumps(json_body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    elif raw_body is not None and content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(BASE_URL + path, data=data, headers=headers, method=method)
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, dict(response.headers), response.read(), (time.monotonic() - started) * 1000
    except urllib.error.HTTPError as exc:
        return exc.code, dict(exc.headers), exc.read(), (time.monotonic() - started) * 1000


def check(
    route: str,
    method: str,
    path: str,
    expected: set[int] | int,
    *,
    token: str | None = None,
    json_body: Any = None,
    raw_body: bytes | None = None,
    content_type: str | None = None,
    mode: str = "functional",
    note: str = "",
    require_content_type: str | None = None,
) -> tuple[int, dict[str, str], bytes]:
    expected_set = {expected} if isinstance(expected, int) else expected
    try:
        status, headers, body, elapsed_ms = request(
            method,
            path,
            token=token,
            json_body=json_body,
            raw_body=raw_body,
            content_type=content_type,
        )
        actual_content_type = headers.get("Content-Type", "")
        passed = status in expected_set
        if require_content_type:
            passed = passed and require_content_type in actual_content_type
        parsed = decode_body(body, actual_content_type)
        results.append(
            {
                "route": route,
                "method": method,
                "status": status,
                "expected": sorted(expected_set),
                "passed": passed,
                "mode": mode,
                "elapsedMs": round(elapsed_ms, 1),
                "contentType": actual_content_type,
                "note": note,
                "response": redact(parsed),
            }
        )
        marker = "PASS" if passed else "FAIL"
        print(f"[{marker}] {method:6} {route:48} {status:3} {elapsed_ms:7.1f} ms", flush=True)
        return status, headers, body
    except Exception as exc:
        results.append(
            {
                "route": route,
                "method": method,
                "status": None,
                "expected": sorted(expected_set),
                "passed": False,
                "mode": mode,
                "elapsedMs": None,
                "contentType": "",
                "note": note,
                "response": f"{type(exc).__name__}: {exc}",
            }
        )
        print(f"[FAIL] {method:6} {route:48} exception={exc}", flush=True)
        return 0, {}, b""


def response_json(body: bytes) -> dict[str, Any]:
    try:
        value = json.loads(body)
        return value if isinstance(value, dict) else {}
    except Exception:
        return {}


def add_cleanup(method: str, path: str, token: str, json_body: Any = None, label: str | None = None) -> None:
    cleanup_actions.append((label or f"{method} {path}", method, path, json_body, token))


def run_cleanup() -> list[dict[str, Any]]:
    outcomes: list[dict[str, Any]] = []
    for label, method, path, body, token in reversed(cleanup_actions):
        try:
            status, _, raw, _ = request(method, path, token=token, json_body=body)
            outcomes.append({"label": label, "status": status, "ok": status in {200, 204, 404}, "response": redact(response_json(raw))})
        except Exception as exc:
            outcomes.append({"label": label, "status": None, "ok": False, "response": str(exc)})
    return outcomes


def ws_open(path: str) -> tuple[socket.socket, int, str]:
    parsed = urllib.parse.urlparse(BASE_URL)
    host = parsed.hostname or ""
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    raw_sock = socket.create_connection((host, port), timeout=30)
    sock: socket.socket
    if parsed.scheme == "https":
        sock = ssl.create_default_context().wrap_socket(raw_sock, server_hostname=host)
    else:
        sock = raw_sock
    sock.settimeout(15)
    key = base64.b64encode(secrets.token_bytes(16)).decode()
    query_path = (parsed.path.rstrip("/") + path) or "/"
    handshake = (
        f"GET {query_path} HTTP/1.1\r\n"
        f"Host: {host}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "User-Agent: posdemo-production-smoke/1.0\r\n\r\n"
    )
    sock.sendall(handshake.encode("ascii"))
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    text = data.decode("latin-1", "replace")
    first_line = text.split("\r\n", 1)[0]
    try:
        status = int(first_line.split()[1])
    except Exception:
        status = 0
    return sock, status, text


def ws_read_frame(sock: socket.socket) -> bytes:
    try:
        header = sock.recv(2)
    except (TimeoutError, socket.timeout):
        return b""
    if len(header) < 2:
        return b""
    length = header[1] & 0x7F
    if length == 126:
        length = struct.unpack("!H", sock.recv(2))[0]
    elif length == 127:
        length = struct.unpack("!Q", sock.recv(8))[0]
    payload = b""
    while len(payload) < length:
        payload += sock.recv(length - len(payload))
    return payload


def record_ws(route: str, status: int, detail: str) -> None:
    passed = status == 101
    results.append(
        {
            "route": route,
            "method": "GET",
            "status": status,
            "expected": [101],
            "passed": passed,
            "mode": "functional",
            "elapsedMs": None,
            "contentType": "websocket",
            "note": detail,
            "response": "<websocket upgraded>" if passed else detail[:500],
        }
    )
    print(f"[{'PASS' if passed else 'FAIL'}] GET    {route:48} {status:3} websocket", flush=True)


def main() -> int:
    global admin_token, pos_secret
    if not ADMIN_PASSWORD:
        print("POS_API_ADMIN_PASSWORD is required", file=sys.stderr)
        return 2

    temp_part = f"SMK{RUN_ID[-10:]}"
    temp_barcode = f"9{RUN_ID[-11:]}"
    auto_address = f"ADDR-{temp_part}-main"
    temp_address = f"ADDR-SMOKE-{RUN_ID}"
    temp_member_phone = "09" + RUN_ID[-8:]
    temp_promo = f"SMOKE{RUN_ID[-8:]}"
    temp_user = f"smoke_{RUN_ID[-10:]}"
    temp_user_password = secrets.token_urlsafe(18)
    temp_user_id = ""
    temp_member_id = ""
    bill_ids: list[str] = []

    cleanup_report: list[dict[str, Any]] = []
    try:
        # Public and authentication.
        check("GET /health", "GET", "/health", 200)
        check("GET /ready", "GET", "/ready", 200)
        check("GET /health/db", "GET", "/health/db", 200)
        check("GET /test", "GET", "/test", 200)
        status, _, body = check(
            "POST /auth/login",
            "POST",
            "/auth/login",
            200,
            json_body={"username": ADMIN_USERNAME, "password": ADMIN_PASSWORD},
        )
        admin_token = response_json(body).get("token", "") if status == 200 else ""
        if not admin_token:
            raise RuntimeError("admin login did not return a token")
        check(
            "POST /auth/verify-password",
            "POST",
            "/auth/verify-password",
            200,
            json_body={"username": ADMIN_USERNAME, "password": ADMIN_PASSWORD},
        )
        check("GET /auth/me", "GET", "/auth/me", 200, token=admin_token)
        check("GET /auth/sessions", "GET", "/auth/sessions", 200, token=admin_token)

        # Read-only baseline and reports.
        check("GET /parts", "GET", "/parts?limit=2", 200, token=admin_token)
        check("GET /parts/search", "GET", "/parts/search?q=P0001&limit=2", 200, token=admin_token)
        check("GET /parts/generate-code", "GET", "/parts/generate-code", 200, token=admin_token)
        check("GET /members", "GET", "/members?limit=2", 200, token=admin_token)
        check("GET /members/search", "GET", "/members/search?q=smoke&limit=2", 200, token=admin_token)
        check("GET /bills", "GET", "/bills?limit=2&statuses=new,hold,completed,cancelled", 200, token=admin_token)
        check("GET /returns", "GET", "/returns?limit=2", 200, token=admin_token)
        check("GET /promotions", "GET", "/promotions?limit=2", 200, token=admin_token)
        check("GET /addresses", "GET", "/addresses?limit=2", 200, token=admin_token)
        check("GET /stores", "GET", "/stores", 200, token=admin_token)
        check("GET /branches", "GET", "/branches?limit=10", 200, token=admin_token)
        check("GET /branches/next-id", "GET", "/branches/next-id", 200, token=admin_token)
        check("GET /pos", "GET", "/pos?limit=20", 200, token=admin_token)
        check("GET /users", "GET", "/users?limit=10", 200, token=admin_token)
        check("GET /roles", "GET", "/roles", 200, token=admin_token)
        check("GET /transfers", "GET", "/transfers?limit=2", 200, token=admin_token)
        check("GET /stock-counts", "GET", "/stock-counts?limit=2", 200, token=admin_token)
        check("GET /daily-closes", "GET", "/daily-closes?limit=2", 200, token=admin_token)
        check(
            "GET /daily-closes/summary",
            "GET",
            "/daily-closes/summary?branchId=00000&posId=POS003",
            200,
            token=admin_token,
        )
        check("GET /cash-reconciliations", "GET", "/cash-reconciliations?limit=2", 200, token=admin_token)
        today = dt.datetime.now(dt.timezone(dt.timedelta(hours=7))).date().isoformat()
        check(
            "GET /reports/bills",
            "GET",
            f"/reports/bills?dateFrom={today}&dateTo={today}&items=1",
            200,
            token=admin_token,
            require_content_type="text/csv",
        )
        check(
            "GET /reports/parts",
            "GET",
            "/reports/parts",
            200,
            token=admin_token,
            require_content_type="text/csv",
        )
        check(
            "GET /reports/inventory",
            "GET",
            "/reports/inventory",
            200,
            token=admin_token,
            require_content_type="text/csv",
        )
        check(
            "GET /reports/income",
            "GET",
            f"/reports/income?dateFrom={today}&dateTo={today}",
            200,
            token=admin_token,
        )
        check(
            "GET /reports/stock-variance",
            "GET",
            f"/reports/stock-variance?countId={FAKE_ID}",
            404,
            token=admin_token,
            mode="validation",
            note="Nonexistent fixture avoids creating an irreversible stock count.",
        )

        # Company is written back byte-for-byte at the JSON field level.
        _, _, company_raw = check("GET /company", "GET", "/company", 200, token=admin_token)
        company = response_json(company_raw)
        check(
            "PUT /company",
            "PUT",
            "/company",
            200,
            token=admin_token,
            json_body={key: company.get(key) for key in (
                "companyName", "companyNameTh", "companyAddress", "companyAddressTh",
                "phone", "email", "website", "logoUrl", "taxRate", "taxType", "receiptFooter",
            )},
            note="Re-saved the current value without a semantic change.",
        )

        # QR image: restore the same bytes when it exists; otherwise validate safely.
        qr_status, qr_headers, qr_body = check(
            "GET /assets/qr-image",
            "GET",
            "/assets/qr-image",
            {200, 404},
            token=admin_token,
            mode="validation",
            note="404 is valid when no QR image is configured.",
        )
        if qr_status == 200:
            check(
                "PUT /assets/qr-image",
                "PUT",
                "/assets/qr-image",
                200,
                token=admin_token,
                raw_body=qr_body,
                content_type=qr_headers.get("Content-Type", "image/png").split(";")[0],
                note="Wrote back the exact existing image bytes.",
            )
        else:
            check(
                "PUT /assets/qr-image",
                "PUT",
                "/assets/qr-image",
                400,
                token=admin_token,
                raw_body=b"not-an-image",
                content_type="image/png",
                mode="validation",
                note="Invalid image exercises validation without creating a new asset.",
            )

        # Exercise branch routes without consuming the monotonic branch ID counter
        # in production. Actual generated-ID/store CRUD is covered by integration
        # tests against a fresh database.
        check(
            "POST /branches",
            "POST",
            "/branches",
            400,
            token=admin_token,
            raw_body=b"[",
            content_type="application/json",
            mode="validation",
            note="Invalid JSON exercises validation without consuming a branch ID.",
        )
        check("GET /branches/:id", "GET", f"/branches/{FAKE_ID}", 404, token=admin_token, mode="validation")
        check(
            "PUT /branches/:id",
            "PUT",
            f"/branches/{FAKE_ID}",
            400,
            token=admin_token,
            json_body={"branchName": "not-created"},
            mode="validation",
        )
        check("DELETE /branches/:id", "DELETE", f"/branches/{FAKE_ID}", 404, token=admin_token, mode="validation")

        # Exercise POS create validation without adding a persistent terminal.
        check("GET /pos/:id", "GET", "/pos/POS003", 200, token=admin_token)
        check(
            "POST /pos",
            "POST",
            "/pos",
            400,
            token=admin_token,
            raw_body=b"[",
            content_type="application/json",
            mode="validation",
            note="Invalid JSON exercises validation without adding a POS.",
        )
        check("PUT /pos/:id/toggle-activate", "PUT", f"/pos/{FAKE_ID}/toggle-activate", 404, token=admin_token, mode="validation")
        _, _, secret_raw = check("GET /pos/:id/secret", "GET", "/pos/POS003/secret", 200, token=admin_token)
        pos_secret = response_json(secret_raw).get("posSecret", "")
        check("PUT /pos/:id/secret", "PUT", f"/pos/{FAKE_ID}/secret", 404, token=admin_token, mode="validation")
        check(
            "DELETE /pos/:id",
            "DELETE",
            f"/pos/{FAKE_ID}",
            200,
            token=admin_token,
            mode="validation",
            note="Current API is idempotent and returns 200 for a nonexistent POS.",
        )
        check(
            "POST /pos/printer/open-drawer",
            "POST",
            "/pos/printer/open-drawer",
            503,
            token=admin_token,
            json_body={},
            mode="expected_config",
            note="Cloud deployment intentionally has printer/cash drawer disabled.",
        )
        check(
            "POST /pos/printer/test-print",
            "POST",
            "/pos/printer/test-print",
            {200, 503},
            token=admin_token,
            json_body={},
            mode="functional",
            note="200 is the Render dev-stub path; 503 is valid when printer output is disabled.",
        )
        check(
            "POST /pos/printer/test-receipt",
            "POST",
            "/pos/printer/test-receipt",
            {200, 503},
            token=admin_token,
            json_body={},
            mode="functional",
            note="200 is the Render dev-stub path; 503 is valid when printer output is disabled.",
        )

        # Product and address CRUD (both addresses are removed before the part).
        status, _, _ = check(
            "POST /parts",
            "POST",
            "/parts",
            201,
            token=admin_token,
            json_body={
                "code": temp_part, "name": "API Smoke Product", "nameTh": "สินค้าทดสอบ API",
                "barcode": temp_barcode, "unitId": "pcs", "price": 10, "cost": 5, "minPrice": 9,
                "details": "temporary fixture", "storeId": "main", "shelf": "SMOKE", "qty": 5,
            },
        )
        if status == 201:
            add_cleanup("DELETE", f"/parts/{temp_part}", admin_token, label="temporary part")
            add_cleanup("DELETE", f"/addresses/{auto_address}", admin_token, label="temporary auto address")
        check("GET /parts/:code", "GET", f"/parts/{temp_part}", 200, token=admin_token)
        check(
            "PUT /parts/:code",
            "PUT",
            f"/parts/{temp_part}",
            200,
            token=admin_token,
            json_body={
                "name": "API Smoke Product Updated", "nameTh": "สินค้าทดสอบ API แก้ไข",
                "barcode": temp_barcode, "unitId": "pcs", "price": 10, "cost": 5, "minPrice": 9,
            },
        )
        status, _, _ = check(
            "POST /addresses",
            "POST",
            "/addresses",
            201,
            token=admin_token,
            json_body={
                "code": temp_address, "partCode": temp_part, "storeId": "main", "shelf": "S2",
                "qty": 0, "min": 0, "max": 10, "rop": 1, "remarks": "temporary fixture",
            },
        )
        if status == 201:
            add_cleanup("DELETE", f"/addresses/{temp_address}", admin_token, label="temporary extra address")
        check("GET /addresses/:code", "GET", f"/addresses/{temp_address}", 200, token=admin_token)
        check(
            "PUT /addresses/:code",
            "PUT",
            f"/addresses/{temp_address}",
            200,
            token=admin_token,
            json_body={
                "partCode": temp_part, "storeId": "main", "shelf": "S3",
                "qty": 0, "min": 0, "max": 12, "rop": 2, "remarks": "updated fixture",
            },
        )
        check("DELETE /addresses/:code", "DELETE", f"/addresses/{temp_address}", 200, token=admin_token)
        cleanup_actions[:] = [action for action in cleanup_actions if action[0] != "temporary extra address"]

        # Member CRUD.
        status, _, member_raw = check(
            "POST /members",
            "POST",
            "/members",
            201,
            token=admin_token,
            json_body={
                "name": "API Smoke Member", "phone": temp_member_phone,
                "email": f"{temp_member_phone}@example.test", "points": 0,
            },
        )
        temp_member_id = response_json(member_raw).get("id", "")
        if status == 201 and temp_member_id:
            add_cleanup("DELETE", f"/members/{temp_member_id}", admin_token, label="temporary member")
        check("GET /members/:id", "GET", f"/members/{temp_member_id}", 200, token=admin_token)
        check(
            "PUT /members/:id",
            "PUT",
            f"/members/{temp_member_id}",
            200,
            token=admin_token,
            json_body={
                "name": "API Smoke Member Updated", "phone": temp_member_phone,
                "email": f"{temp_member_phone}@example.test", "points": 1,
            },
        )

        # Promotion CRUD.
        status, _, _ = check(
            "POST /promotions",
            "POST",
            "/promotions",
            201,
            token=admin_token,
            json_body={"code": temp_promo, "details": "temporary fixture", "unit": "THB", "amount": 1},
        )
        if status == 201:
            add_cleanup("DELETE", f"/promotions/{temp_promo}", admin_token, label="temporary promotion")
        check("GET /promotions/:code", "GET", f"/promotions/{temp_promo}", 200, token=admin_token)
        check(
            "PUT /promotions/:code",
            "PUT",
            f"/promotions/{temp_promo}",
            200,
            token=admin_token,
            json_body={"details": "temporary fixture updated", "unit": "THB", "amount": 1},
        )

        # Role creation has no delete counterpart.
        check(
            "POST /roles",
            "POST",
            "/roles",
            400,
            token=admin_token,
            json_body={"name": "", "detail": "", "permissions": []},
            mode="validation",
            note="No role-delete route exists, so creation validation is tested safely.",
        )

        # Reversible user + user-branch CRUD, and safe auth session revocation.
        status, _, user_raw = check(
            "POST /users",
            "POST",
            "/users",
            201,
            token=admin_token,
            json_body={
                "username": temp_user, "roleId": "role.hq_manager", "name": "API Smoke User",
                "password": temp_user_password, "isActive": True, "isSuperuser": False,
                "customPermissions": [],
            },
        )
        temp_user_id = response_json(user_raw).get("id", "")
        if status == 201 and temp_user_id:
            add_cleanup("DELETE", f"/users/{temp_user_id}", admin_token, label="temporary user")
        check("GET /users/:id", "GET", f"/users/{temp_user_id}", 200, token=admin_token)
        check(
            "PUT /users/:id",
            "PUT",
            f"/users/{temp_user_id}",
            200,
            token=admin_token,
            json_body={
                "username": temp_user, "roleId": "role.hq_manager", "name": "API Smoke User Updated",
                "isActive": True, "isSuperuser": False, "customPermissions": [],
            },
        )
        status, _, _ = check(
            "POST /user-branches",
            "POST",
            "/user-branches",
            201,
            token=admin_token,
            json_body={"userId": temp_user_id, "branchId": "00000"},
        )
        if status == 201:
            add_cleanup("DELETE", f"/user-branches/{temp_user_id}/00000", admin_token, label="temporary user branch")
        check("GET /user-branches/user/:user_id", "GET", f"/user-branches/user/{temp_user_id}", 200, token=admin_token)
        check("GET /user-branches/branch/:branch_id", "GET", "/user-branches/branch/00000", 200, token=admin_token)
        check(
            "GET /user-branches/:user_id/:branch_id",
            "GET",
            f"/user-branches/{temp_user_id}/00000",
            200,
            token=admin_token,
        )
        login_status, _, temp_login_raw = check(
            "POST /auth/login",
            "POST",
            "/auth/login",
            200,
            json_body={"username": temp_user, "password": temp_user_password},
            note="Second invocation uses the temporary user for session lifecycle isolation.",
        )
        temp_token = response_json(temp_login_raw).get("token", "") if login_status == 200 else ""
        check("POST /auth/sessions/revoke-others", "POST", "/auth/sessions/revoke-others", 200, token=temp_token, json_body={})
        check("POST /auth/logout", "POST", "/auth/logout", 200, token=temp_token, json_body={})
        check(
            "DELETE /user-branches/:user_id/:branch_id",
            "DELETE",
            f"/user-branches/{temp_user_id}/00000",
            200,
            token=admin_token,
        )
        cleanup_actions[:] = [action for action in cleanup_actions if action[0] != "temporary user branch"]
        check("DELETE /users/:id", "DELETE", f"/users/{temp_user_id}", 200, token=admin_token)
        cleanup_actions[:] = [action for action in cleanup_actions if action[0] != "temporary user"]

        # Bill flow. If the production POS already has an active bill, do not touch it.
        bill_status, _, bill_raw = check("POST /bills", "POST", "/bills", {201, 409}, token=admin_token, json_body={})
        bill_id = response_json(bill_raw).get("id", "")
        if bill_status == 201 and bill_id:
            bill_ids.append(bill_id)
            add_cleanup("DELETE", f"/bills/{bill_id}", admin_token, label=f"temporary bill {bill_id}")
            check("GET /bills/:id", "GET", f"/bills/{bill_id}", 200, token=admin_token)
            check(
                "PUT /bills/:id/add-item",
                "PUT",
                f"/bills/{bill_id}/add-item",
                200,
                token=admin_token,
                json_body={"partCode": temp_part, "addressCode": auto_address, "qty": 1},
            )
            check(
                "PUT /bills/:id/add-item-by-barcode",
                "PUT",
                f"/bills/{bill_id}/add-item-by-barcode",
                200,
                token=admin_token,
                json_body={"barcode": temp_barcode, "qty": 1},
            )
            check(
                "PUT /bills/:id/remove-item",
                "PUT",
                f"/bills/{bill_id}/remove-item",
                200,
                token=admin_token,
                json_body={"partCode": temp_part, "addressCode": auto_address, "qty": 1, "isRemoveAll": False},
            )
            check(
                "PUT /bills/:id/update-item-price",
                "PUT",
                f"/bills/{bill_id}/update-item-price",
                200,
                token=admin_token,
                json_body={"partCode": temp_part, "addressCode": auto_address, "lineTotal": 10},
            )
            check(
                "PUT /bills/:id/add-discount",
                "PUT",
                f"/bills/{bill_id}/add-discount",
                200,
                token=admin_token,
                json_body={"promotionCode": temp_promo},
            )
            check(
                "PUT /bills/:id/remove-discount",
                "PUT",
                f"/bills/{bill_id}/remove-discount",
                200,
                token=admin_token,
                json_body={"promotionCode": temp_promo},
            )
            check(
                "PUT /bills/:id/add-member-by-phone",
                "PUT",
                f"/bills/{bill_id}/add-member-by-phone",
                200,
                token=admin_token,
                json_body={"phone": temp_member_phone},
            )
            check("PUT /bills/:id/remove-member", "PUT", f"/bills/{bill_id}/remove-member", 200, token=admin_token, json_body={})
            check(
                "POST /bills/:id/print",
                "POST",
                f"/bills/{bill_id}/print",
                {200, 400, 503},
                token=admin_token,
                json_body={"idempotencyKey": f"smoke-{RUN_ID}"},
                mode="functional",
                note="The dev stub may return 200; an unfinished bill or disabled printer returns 400/503.",
            )
            check(
                "PUT /bills/:id/remove-item",
                "PUT",
                f"/bills/{bill_id}/remove-item",
                200,
                token=admin_token,
                json_body={"partCode": temp_part, "addressCode": auto_address, "isRemoveAll": True},
                note="Second invocation empties the fixture before cancellation to prevent stock double-return.",
            )
            check(
                "PUT /bills/:id/payment",
                "PUT",
                f"/bills/{bill_id}/payment",
                400,
                token=admin_token,
                json_body={"paymentMethod": "cash"},
                mode="validation",
                note="An empty bill exercises payment validation without creating an accounting record.",
            )
            check("PUT /bills/:id/hold", "PUT", f"/bills/{bill_id}/hold", 200, token=admin_token, json_body={})
            switch_status, _, switch_raw = check(
                "PUT /bills/switch",
                "PUT",
                "/bills/switch",
                200,
                token=admin_token,
                json_body={},
            )
            second_bill = response_json(switch_raw).get("id", "") or response_json(switch_raw).get("billId", "")
            if switch_status == 200 and second_bill:
                bill_ids.append(second_bill)
                add_cleanup("DELETE", f"/bills/{second_bill}", admin_token, label=f"temporary bill {second_bill}")
                check(
                    "PUT /bills/switch",
                    "PUT",
                    "/bills/switch",
                    200,
                    token=admin_token,
                    json_body={"targetBillId": bill_id},
                    note="Second invocation covers resuming a held bill and holding the current bill.",
                )
                check("PUT /bills/:id/cancel", "PUT", f"/bills/{bill_id}/cancel", 200, token=admin_token, json_body={})
                check("DELETE /bills/:id", "DELETE", f"/bills/{bill_id}", 200, token=admin_token)
                cleanup_actions[:] = [action for action in cleanup_actions if action[0] != f"temporary bill {bill_id}"]
                check(
                    "PUT /bills/:id/cancel",
                    "PUT",
                    f"/bills/{second_bill}/cancel",
                    200,
                    token=admin_token,
                    json_body={},
                    note="Second invocation cleans the bill created by switch.",
                )
                check(
                    "DELETE /bills/:id",
                    "DELETE",
                    f"/bills/{second_bill}",
                    200,
                    token=admin_token,
                    note="Second invocation cleans the bill created by switch.",
                )
                cleanup_actions[:] = [action for action in cleanup_actions if action[0] != f"temporary bill {second_bill}"]
        else:
            # Route coverage without touching the user's active bill.
            for route, method, suffix, body_value in [
                ("GET /bills/:id", "GET", "", None),
                ("PUT /bills/:id/add-item", "PUT", "/add-item", {}),
                ("PUT /bills/:id/add-item-by-barcode", "PUT", "/add-item-by-barcode", {}),
                ("PUT /bills/:id/remove-item", "PUT", "/remove-item", {}),
                ("PUT /bills/:id/update-item-price", "PUT", "/update-item-price", {}),
                ("PUT /bills/:id/add-discount", "PUT", "/add-discount", {}),
                ("PUT /bills/:id/remove-discount", "PUT", "/remove-discount", {}),
                ("PUT /bills/:id/add-member-by-phone", "PUT", "/add-member-by-phone", {}),
                ("PUT /bills/:id/remove-member", "PUT", "/remove-member", {}),
                ("PUT /bills/:id/hold", "PUT", "/hold", {}),
                ("PUT /bills/:id/payment", "PUT", "/payment", {}),
                ("POST /bills/:id/print", "POST", "/print", {}),
                ("PUT /bills/:id/cancel", "PUT", "/cancel", {}),
                ("DELETE /bills/:id", "DELETE", "", None),
            ]:
                check(route, method, f"/bills/{FAKE_ID}{suffix}", {400, 404, 503}, token=admin_token, json_body=body_value, mode="validation")
            check("PUT /bills/switch", "PUT", "/bills/switch", 404, token=admin_token, json_body={"targetBillId": FAKE_ID}, mode="validation")
        check(
            "POST /bills/print-test",
            "POST",
            "/bills/print-test",
            {200, 503},
            token=admin_token,
            json_body={},
            mode="functional",
            note="200 is the Render dev-stub path; 503 is valid when printer output is disabled.",
        )

        # Returns: read routes plus non-persisting create/print checks.
        check("GET /returns/reference/:billId", "GET", f"/returns/reference/{FAKE_ID}", 404, token=admin_token, mode="validation")
        check("GET /returns/:id", "GET", f"/returns/{FAKE_ID}", 404, token=admin_token, mode="validation")
        check(
            "POST /returns",
            "POST",
            "/returns",
            404,
            token=admin_token,
            json_body={
                "referenceBillId": FAKE_ID, "settlementMode": "cash_refund",
                "lines": [{"partCode": temp_part, "addressCode": auto_address, "qty": 1}],
            },
            mode="validation",
            note="A nonexistent reference avoids an irreversible completed return note.",
        )
        check(
            "POST /returns/:id/print",
            "POST",
            f"/returns/{FAKE_ID}/print",
            {404, 503},
            token=admin_token,
            json_body={"idempotencyKey": f"return-smoke-{RUN_ID}"},
            mode="validation",
            note="The printer gate may return 503 before lookup; the Render dev stub reaches the safe 404 lookup.",
        )

        # Inbound purchase orders expose costs and are admin-only. Exercise the
        # read routes plus validation without adding production stock.
        check("GET /purchase-orders", "GET", "/purchase-orders?limit=5", 200, token=admin_token)
        check(
            "GET /purchase-orders/:id",
            "GET",
            f"/purchase-orders/{FAKE_ID}",
            404,
            token=admin_token,
            mode="validation",
        )
        check(
            "POST /purchase-orders",
            "POST",
            "/purchase-orders",
            400,
            token=admin_token,
            json_body={"requestId": f"validation-{RUN_ID}", "items": []},
            mode="validation",
            note="An empty item list validates the route without receiving stock.",
        )

        # Irreversible operational documents are exercised through validation/not-found paths.
        check(
            "GET /transfers/pos-restock/catalog",
            "GET",
            "/transfers/pos-restock/catalog?limit=1",
            200,
            token=admin_token,
        )
        today_bangkok = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=7)).date().isoformat()
        check(
            "GET /transfers/vehicle-daily-summary",
            "GET",
            f"/transfers/vehicle-daily-summary?posId=POS001&date={today_bangkok}",
            200,
            token=admin_token,
        )
        check(
            "GET /vehicle-inventory",
            "GET",
            f"/vehicle-inventory?posId=POS001&dateFrom={today_bangkok}&dateTo={today_bangkok}",
            200,
            token=admin_token,
        )
        check("GET /transfers/:id", "GET", f"/transfers/{FAKE_ID}", 404, token=admin_token, mode="validation")
        check("POST /transfers", "POST", "/transfers", 400, token=admin_token, json_body={}, mode="validation")
        check(
            "POST /transfers/pos-restock",
            "POST",
            "/transfers/pos-restock",
            400,
            token=admin_token,
            raw_body=b"[",
            content_type="application/json",
            mode="validation",
        )
        for route, suffix, body_value in [
            ("PUT /transfers/:id/items", "items", {"items": []}),
            ("PUT /transfers/:id/submit", "submit", {}),
            ("PUT /transfers/:id/receive", "receive", {}),
            ("PUT /transfers/:id/cancel", "cancel", {}),
            ("PUT /transfers/:id/approve", "approve", {}),
            ("PUT /transfers/:id/dispatch", "dispatch", {}),
            ("PUT /transfers/:id/acknowledge", "acknowledge", {}),
            ("PUT /transfers/:id/approve-restock", "approve-restock", {}),
        ]:
            check(route, "PUT", f"/transfers/{FAKE_ID}/{suffix}", {400, 404}, token=admin_token, json_body=body_value, mode="validation")
        check(
            "POST /transfers/:id/print-log",
            "POST",
            f"/transfers/{FAKE_ID}/print-log",
            404,
            token=admin_token,
            json_body={},
            mode="validation",
        )

        check("GET /stock-counts/:id", "GET", f"/stock-counts/{FAKE_ID}", 404, token=admin_token, mode="validation")
        check("POST /stock-counts", "POST", "/stock-counts", 400, token=admin_token, json_body={}, mode="validation")
        check(
            "PUT /stock-counts/:id/items",
            "PUT",
            f"/stock-counts/{FAKE_ID}/items",
            404,
            token=admin_token,
            json_body={"items": []},
            mode="validation",
        )
        check("PUT /stock-counts/:id/submit", "PUT", f"/stock-counts/{FAKE_ID}/submit", 404, token=admin_token, json_body={}, mode="validation")

        check("GET /daily-closes/:id", "GET", f"/daily-closes/{FAKE_ID}", 404, token=admin_token, mode="validation")
        check("POST /daily-closes", "POST", "/daily-closes", 400, token=admin_token, json_body={}, mode="validation")
        check("GET /cash-reconciliations/:id", "GET", f"/cash-reconciliations/{FAKE_ID}", 404, token=admin_token, mode="validation")
        check("POST /cash-reconciliations", "POST", "/cash-reconciliations", 400, token=admin_token, json_body={}, mode="validation")

        # WebSocket upgrade and in-memory customer display state.
        mirror_sock = None
        display_sock = None
        try:
            mirror_sock, mirror_status, mirror_detail = ws_open(f"/ws/pos-mirror?token={urllib.parse.quote(admin_token)}")
            record_ws("GET /ws/pos-mirror", mirror_status, mirror_detail)
            if mirror_status == 101:
                ws_read_frame(mirror_sock)
        finally:
            if mirror_sock:
                mirror_sock.close()
        try:
            display_sock, display_status, display_detail = ws_open(
                "/ws/customer-display?"
                + urllib.parse.urlencode({"branchId": "00000", "posId": "POS003", "posSecret": pos_secret})
            )
            record_ws("GET /ws/customer-display", display_status, display_detail)
            check(
                "POST /pos-mirror/test-state",
                "POST",
                "/pos-mirror/test-state",
                200,
                token=admin_token,
                json_body={"lastAction": f"production_smoke_{RUN_ID}"},
                note="Publishes only ephemeral in-memory display state.",
            )
            if display_status == 101:
                ws_read_frame(display_sock)
        finally:
            if display_sock:
                display_sock.close()

        # Delete remaining reversible fixtures in dependency order.
        check("DELETE /members/:id", "DELETE", f"/members/{temp_member_id}", 200, token=admin_token)
        cleanup_actions[:] = [action for action in cleanup_actions if action[0] != "temporary member"]
        check("DELETE /promotions/:code", "DELETE", f"/promotions/{temp_promo}", 200, token=admin_token)
        cleanup_actions[:] = [action for action in cleanup_actions if action[0] != "temporary promotion"]
        check("DELETE /addresses/:code", "DELETE", f"/addresses/{auto_address}", 200, token=admin_token)
        cleanup_actions[:] = [action for action in cleanup_actions if action[0] != "temporary auto address"]
        _, _, delete_part_raw = check(
            "DELETE /parts/:code",
            "DELETE",
            f"/parts/{temp_part}",
            200,
            token=admin_token,
        )
        if response_json(delete_part_raw).get("mode") != "deleted":
            raise RuntimeError("unreferenced temporary product was not hard-deleted")
        cleanup_actions[:] = [action for action in cleanup_actions if action[0] != "temporary part"]
    finally:
        cleanup_report = run_cleanup()
        if admin_token:
            try:
                request("POST", "/auth/logout", token=admin_token, json_body={})
            except Exception:
                pass

        expected_routes = {
            line.strip()
            for line in ROUTE_MANIFEST.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        }
        observed_routes = {row["route"] for row in results}
        missing_routes = sorted(expected_routes - observed_routes)
        unexpected_routes = sorted(observed_routes - expected_routes)
        passed = sum(1 for row in results if row["passed"])
        failed = len(results) - passed
        report = {
            "runId": RUN_ID,
            "baseUrl": BASE_URL,
            "startedForDate": dt.datetime.now(dt.timezone.utc).isoformat(),
            "summary": {
                "calls": len(results),
                "uniqueRoutes": len(observed_routes),
                "passedCalls": passed,
                "failedCalls": failed,
                "expectedRouterRoutes": len(expected_routes),
                "coverageComplete": not missing_routes and not unexpected_routes,
                "missingRoutes": missing_routes,
                "unexpectedRoutes": unexpected_routes,
                "cleanupOk": all(row["ok"] for row in cleanup_report),
            },
            "cleanup": cleanup_report,
            "results": results,
        }
        REPORT_DIR.mkdir(parents=True, exist_ok=True)
        report_path = REPORT_DIR / f"production-api-smoke-{RUN_ID}.json"
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\nReport: {report_path}", flush=True)
        print(json.dumps(report["summary"], ensure_ascii=False, indent=2), flush=True)

    return 0 if results and all(row["passed"] for row in results) and not missing_routes and not unexpected_routes and all(row["ok"] for row in cleanup_report) else 1


if __name__ == "__main__":
    raise SystemExit(main())
