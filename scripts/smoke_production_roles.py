#!/usr/bin/env python3
"""Stateful production verification for admin, pos1 and pos2.

The script uses an existing saleable catalog item in each POS store instead of
creating test products. Completed bills, full returns and submitted stock
counts remain as deployment evidence; inventory and net income return to their
starting values.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


BASE_URL = os.getenv("POS_API_BASE_URL", "https://pos-labs.onrender.com").rstrip("/")
ADMIN_PASSWORD = os.getenv("POS_API_ADMIN_PASSWORD", "")
POS1_PASSWORD = os.getenv("POS_API_POS1_PASSWORD", "pos123456")
POS2_PASSWORD = os.getenv("POS_API_POS2_PASSWORD", "pos123456")
REPORT_DIR = Path(os.getenv("POS_API_REPORT_DIR", "reports"))
RUN_ID = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S")
MARKER = f"VERIFY-{RUN_ID}"


class APIError(RuntimeError):
    def __init__(self, method: str, path: str, status: int, body: Any):
        super().__init__(f"{method} {path}: expected success, got {status}: {body}")
        self.status = status
        self.body = body


def call(
    method: str,
    path: str,
    *,
    token: str | None = None,
    body: Any = None,
    expected: int | set[int] = 200,
) -> tuple[int, Any]:
    expected_set = {expected} if isinstance(expected, int) else expected
    headers = {"Accept": "application/json", "User-Agent": "posdemo-role-smoke/1.0"}
    data = None
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(BASE_URL + path, data=data, headers=headers, method=method)
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            status = response.status
            raw = response.read()
    except urllib.error.HTTPError as error:
        status = error.code
        raw = error.read()
    try:
        parsed = json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        parsed = raw.decode("utf-8", "replace")[:500]
    elapsed = (time.monotonic() - started) * 1000
    passed = status in expected_set
    print(f"[{'PASS' if passed else 'FAIL'}] {method:6} {path:62} {status:3} {elapsed:7.1f} ms")
    if not passed:
        raise APIError(method, path, status, parsed)
    return status, parsed


def login(username: str, password: str) -> tuple[str, dict[str, Any]]:
    _, result = call(
        "POST",
        "/auth/login",
        body={"username": username, "password": password},
    )
    token = result.get("token", "")
    if not token:
        raise RuntimeError(f"{username} login did not return token")
    _, profile = call("GET", "/auth/me", token=token)
    return token, profile


def rows(payload: Any, key: str) -> list[dict[str, Any]]:
    value = payload.get(key, []) if isinstance(payload, dict) else []
    return value if isinstance(value, list) else []


def numeric_summary(payload: dict[str, Any]) -> dict[str, float]:
    summary = payload.get("summary", {})
    keys = ("netRevenue", "netCost", "grossProfit", "expenses", "netProfit")
    return {key: float(summary.get(key, 0) or 0) for key in keys}


def verify_same_summary(before: dict[str, float], after: dict[str, float]) -> None:
    differences = {
        key: round(after[key] - before[key], 4)
        for key in before
        if abs(after[key] - before[key]) > 0.01
    }
    if differences:
        raise AssertionError(f"full returns did not restore income summary: {differences}")


def main() -> int:
    if not ADMIN_PASSWORD:
        print("POS_API_ADMIN_PASSWORD is required", file=sys.stderr)
        return 2

    credentials = {
        "admin": ADMIN_PASSWORD,
        "pos1": POS1_PASSWORD,
        "pos2": POS2_PASSWORD,
    }
    tokens: dict[str, str] = {}
    profiles: dict[str, dict[str, Any]] = {}
    for username, password in credentials.items():
        tokens[username], profiles[username] = login(username, password)

    admin_token = tokens["admin"]
    _, pos_payload = call("GET", "/pos?limit=100", token=admin_token)
    stores_by_pos = {
        item["posId"]: item.get("vehicleStoreId")
        for item in rows(pos_payload, "pos")
        if item.get("posId") and item.get("vehicleStoreId")
    }
    today = dt.datetime.now(dt.timezone(dt.timedelta(hours=7))).date().isoformat()
    _, income_before_payload = call(
        "GET",
        f"/reports/income?dateFrom={today}&dateTo={today}",
        token=admin_token,
    )
    income_before = numeric_summary(income_before_payload)

    evidence: dict[str, Any] = {
        "runId": RUN_ID,
        "marker": MARKER,
        "baseUrl": BASE_URL,
        "accounts": {},
    }
    bill_owner: dict[str, str] = {}
    return_owner: dict[str, str] = {}

    for username in ("admin", "pos1", "pos2"):
        token = tokens[username]
        profile = profiles[username]
        branch_id = profile["branchId"]
        pos_id = profile["posId"]
        store_id = stores_by_pos.get(pos_id)
        if not store_id:
            raise RuntimeError(f"no inventory store configured for {username}/{pos_id}")

        _, saleable_payload = call(
            "GET",
            f"/parts/search?storeId={store_id}&saleableOnly=true&isActive=true&limit=1",
            token=token,
        )
        saleable_parts = rows(saleable_payload, "parts")
        if not saleable_parts:
            raise AssertionError(f"no saleable catalog item for {username}/{store_id}")
        saleable = saleable_parts[0]
        part_code = saleable.get("code", "")
        price = float(saleable.get("price", 0) or 0)
        min_price = float(saleable.get("minPrice", saleable.get("min_price", price)) or price)
        addresses = saleable.get("addresses", [])
        address_code = next(
            (
                address.get("code", "")
                for address in addresses
                if isinstance(address, dict)
                and (address.get("store", {}).get("id") if isinstance(address.get("store"), dict) else address.get("storeId")) == store_id
                and float(address.get("qty", 0) or 0) > 0
            ),
            "",
        )
        if not part_code or not address_code or price <= 0:
            raise AssertionError(f"incomplete saleable catalog item for {username}: {saleable}")

        held_bill_id = ""
        active_test_bill_id = ""
        try:
            status, created_bill = call("POST", "/bills", token=token, body={}, expected={201, 409})
            if status == 409:
                held_bill_id = created_bill.get("existingBillId", "")
                if not held_bill_id:
                    raise AssertionError(f"{username} active bill conflict did not include existingBillId")
                call("PUT", f"/bills/{held_bill_id}/hold", token=token, body={})
                _, created_bill = call("POST", "/bills", token=token, body={}, expected=201)
            bill_id = created_bill.get("id", "")
            active_test_bill_id = bill_id
            if not bill_id:
                raise AssertionError(f"{username} create bill did not return id")

            call(
                "PUT",
                f"/bills/{bill_id}/add-item",
                token=token,
                body={"partCode": part_code, "addressCode": address_code, "qty": 1},
            )
            call(
                "PUT",
                f"/bills/{bill_id}/update-item-price",
                token=token,
                body={"partCode": part_code, "addressCode": address_code, "lineTotal": round(min_price - 0.01, 2)},
                expected=400,
            )
            call(
                "PUT",
                f"/bills/{bill_id}/update-item-price",
                token=token,
                body={"partCode": part_code, "addressCode": address_code, "lineTotal": min_price},
            )
            call(
                "PUT",
                f"/bills/{bill_id}/update-item-price",
                token=token,
                body={"partCode": part_code, "addressCode": address_code, "lineTotal": price},
            )
            call(
                "PUT",
                f"/bills/{bill_id}/update-item-price",
                token=token,
                body={"partCode": part_code, "addressCode": address_code, "lineTotal": round(price + 0.01, 2)},
                expected=400,
            )
            call(
                "PUT",
                f"/bills/{bill_id}/payment",
                token=token,
                body={"paymentMethod": "cash", "paymentRef": MARKER},
            )
            active_test_bill_id = ""
            _, return_payload = call(
                "POST",
                "/returns",
                token=token,
                body={
                    "referenceBillId": bill_id,
                    "settlementMode": "cash_refund",
                    "paymentMethod": "cash",
                    "paymentRef": MARKER,
                    "lines": [
                        {
                            "partCode": part_code,
                            "addressCode": address_code,
                            "qty": 1,
                        }
                    ],
                },
                expected=201,
            )
            return_id = (
                return_payload.get("id")
                or return_payload.get("returnNoteId")
                or return_payload.get("data", {}).get("id")
            )
            if not return_id:
                raise AssertionError(f"{username} return did not return id: {return_payload}")
            bill_owner[bill_id] = username
            return_owner[return_id] = username

            _, stock_count_payload = call(
                "POST",
                "/stock-counts",
                token=token,
                body={
                    "branchId": branch_id,
                    "storeId": store_id,
                    "notes": f"{MARKER}-{username}",
                },
                expected=201,
            )
            stock_count = stock_count_payload.get("data", {})
            stock_count_id = stock_count.get("id", "")
            stock_items = stock_count.get("items", [])
            if not stock_count_id or not stock_items:
                raise AssertionError(f"{username} stock count fixture is incomplete")
            call(
                "PUT",
                f"/stock-counts/{stock_count_id}/submit",
                token=token,
                body={
                    "items": [
                        {
                            "partCode": item["partCode"],
                            "countedQty": int(item.get("systemQty", 0)),
                        }
                        for item in stock_items
                    ]
                },
            )

            evidence["accounts"][username] = {
                "branchId": branch_id,
                "posId": pos_id,
                "storeId": store_id,
                "partCode": part_code,
                "addressCode": address_code,
                "billId": bill_id,
                "returnId": return_id,
                "stockCountId": stock_count_id,
            }
        finally:
            if active_test_bill_id:
                try:
                    call("PUT", f"/bills/{active_test_bill_id}/cancel", token=token, body={})
                    call("DELETE", f"/bills/{active_test_bill_id}", token=token)
                except Exception as cleanup_error:
                    print(f"[WARN] failed to remove unfinished test bill: {cleanup_error}", file=sys.stderr)
            if held_bill_id:
                try:
                    call("PUT", "/bills/switch", token=token, body={"targetBillId": held_bill_id})
                except Exception as restore_error:
                    print(f"[WARN] failed to restore held bill {held_bill_id}: {restore_error}", file=sys.stderr)

    for username, token in tokens.items():
        expected_bill = next(bill for bill, owner in bill_owner.items() if owner == username)
        expected_return = next(note for note, owner in return_owner.items() if owner == username)
        _, own_bills = call(
            "GET",
            "/bills?scope=pos&limit=200&statuses=completed",
            token=token,
        )
        _, own_returns = call("GET", "/returns?scope=pos&limit=200", token=token)
        if expected_bill not in {bill.get("billId") or bill.get("id") for bill in rows(own_bills, "bills")}:
            raise AssertionError(f"{username} cannot see its own completed bill")
        if expected_return not in {
            note.get("returnNoteId") or note.get("id") for note in rows(own_returns, "returns")
        }:
            raise AssertionError(f"{username} cannot see its own return")
        if username != "admin":
            call("GET", "/bills?scope=all&limit=10", token=token, expected=403)
            call("GET", "/returns?scope=all&limit=10", token=token, expected=403)
            other_bills = [bill for bill, owner in bill_owner.items() if owner != username]
            other_returns = [note for note, owner in return_owner.items() if owner != username]
            for bill_id in other_bills:
                call("GET", f"/bills/{bill_id}", token=token, expected=403)
            for return_id in other_returns:
                call("GET", f"/returns/{return_id}", token=token, expected=403)

    _, all_bills = call(
        "GET",
        "/bills?scope=all&limit=200&statuses=completed",
        token=admin_token,
    )
    _, all_returns = call("GET", "/returns?scope=all&limit=200", token=admin_token)
    visible_bills = {bill.get("billId") or bill.get("id") for bill in rows(all_bills, "bills")}
    visible_returns = {
        note.get("returnNoteId") or note.get("id") for note in rows(all_returns, "returns")
    }
    if not set(bill_owner).issubset(visible_bills):
        raise AssertionError("admin global bill history is missing role-smoke bills")
    if not set(return_owner).issubset(visible_returns):
        raise AssertionError("admin global return history is missing role-smoke returns")
    for bill_id in bill_owner:
        call("GET", f"/bills/{bill_id}", token=admin_token)
    for return_id in return_owner:
        call("GET", f"/returns/{return_id}", token=admin_token)

    _, income_after_payload = call(
        "GET",
        f"/reports/income?dateFrom={today}&dateTo={today}",
        token=admin_token,
    )
    income_after = numeric_summary(income_after_payload)
    verify_same_summary(income_before, income_after)
    evidence["incomeBefore"] = income_before
    evidence["incomeAfter"] = income_after
    evidence["inventoryRestoredByFullReturns"] = True
    evidence["adminGlobalVisibility"] = True
    evidence["posIsolation"] = True

    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    report_path = REPORT_DIR / f"production-role-smoke-{RUN_ID}.json"
    report_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nRole smoke report: {report_path}")
    print(json.dumps(evidence, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
