# POS Labs — คู่มือการทดสอบระบบ (Handbook)

> **วัตถุประสงค์**: คู่มือนี้ใช้สำหรับทดสอบระบบ POS Labs จากการใช้งานจริงทุกขั้นตอน
> แต่ละ Case มี Flow สรุป และ Checklist ท้ายเอกสารให้ติ๊กว่าผ่านหรือไม่

---

## สภาพแวดล้อมการทดสอบ

### วิธี Run ระบบ

```bash
# Terminal 1 — Backend + DB
cd /path/to/posdemo
docker-compose down -v && docker-compose up --build

# Terminal 2 — Frontend (build ครั้งเดียว แล้ว serve 3 port)
cd /path/to/posdemo/frontend
flutter build web --profile
python3 -m http.server 8081 --directory build/web &
python3 -m http.server 8082 --directory build/web &
python3 -m http.server 8083 --directory build/web &
```

### บัญชีผู้ใช้ทดสอบ

| URL | Username | Password | Role | หน้าที่ |
|---|---|---|---|---|
| `localhost:8081` | `admin` | `admin123` | Super Admin | จัดการระบบทั้งหมด |
| `localhost:8082` | `hqmanager` | `hq123456` | HQ Manager | จัดการ HQ / ดูรายงาน |
| `localhost:8083` | `pos1` | `pos123456` | Van Staff | ขายของบนรถแวน |

---

## ภาพรวมโครงสร้าง Pages ต่อ Role

### Super Admin (admin)
เข้าถึงได้ทั้งหมด — เข้าสู่ **Backoffice** โดยอัตโนมัติหลัง Login

| Section | เมนู | ใช้ทำอะไร |
|---|---|---|
| ORGANIZATION | Users | จัดการ user ทุกคน |
| | User-Branches | กำหนดว่า user คนไหนเข้าสาขาไหนได้ |
| | Company | ข้อมูลบริษัท |
| | Branches | จัดการสาขา |
| | POS | จัดการเครื่อง POS |
| MASTER DATA | Parts | จัดการสินค้า |
| | Addresses | จัดการที่อยู่สินค้าในคลัง |
| | Promotions | จัดการโปรโมชัน |
| | Members | ดูรายชื่อสมาชิก |
| OPERATIONS | Bills | ประวัติบิลทุกสาขา |
| | Returns | ประวัติการคืนสินค้า |
| | Reports | Export CSV |
| | Payment | ตั้งค่า QR Payment |
| | Transfers | โอนสินค้า HQ → รถแวน |
| | Cash Recon | ยืนยันรับเงินจากรถ |
| | Variance | รายงานส่วนต่างสต๊อก |
| SUPPORT | Support POS | Monitor หน้าจอ Van Staff แบบ Real-time |

### HQ Manager (hqmanager)
เข้าสู่ **Backoffice** โดยอัตโนมัติ — ไม่เห็น ORGANIZATION และ SUPPORT

| Section | เมนู |
|---|---|
| MASTER DATA | Parts, Addresses, Promotions, Members |
| OPERATIONS | Bills, Returns, Reports, Payment, Transfers, Cash Recon, Variance |

### Van Staff (pos1)
เข้าสู่ **POS Screen** โดยอัตโนมัติ — ไม่มี Backoffice

| ปุ่มบน Header | ไอคอน | ใช้ทำอะไร |
|---|---|---|
| คืนสินค้า | 🔴 | เปิดใบคืนสินค้า (อ้างอิงบิลเดิม) |
| พักบิล | ⏸ | พักบิลปัจจุบัน เปิดบิลใหม่ |
| ส่วนลด | ⚠ | ส่วนลดพิเศษ |
| ประวัติบิล | 🕐 | ดูบิลที่ขายไปแล้ว |
| เพิ่มสมาชิก | 👤+ | ลงทะเบียนสมาชิกใหม่ |
| นับสต๊อก | 📦 | เปิดหน้านับสินค้าในรถ |
| ปิดยอด | 🧮 | ปิดยอดขายประจำวัน |
| รับสินค้าโอน | 🚚 | รับสินค้าที่ HQ ส่งมาให้ |
| คำขอเบิกสินค้า | 📋 | ส่งคำขอเบิกสินค้าจาก HQ / ติดตามสถานะ |
| Customer Screen | 🖥 | เปิดหน้าจอลูกค้า (จอที่ 2) |

---

## Case 1: การขายสินค้าพื้นฐาน (Van Staff)

**สถานการณ์**: Van Staff ขายสินค้าให้ลูกค้า รับเงินสด

### ขั้นตอน

1. Login ที่ `localhost:8083` ด้วย `pos1 / pos123456`
   - ✅ ต้องเข้าหน้า POS โดยตรง (ไม่ใช่ Backoffice)

2. พิมพ์ชื่อสินค้าในช่อง "พิมพ์ค้นหาสินค้า" หรือสแกนบาร์โค้ด
   - ทดสอบ: พิมพ์ `Sample` แล้ว Enter → เลือกสินค้า

3. สินค้าเข้าตะกร้า → ราคารวมอัปเดต

4. กด **"ชำระเงิน"**

5. เลือก **เงินสด** → กรอกจำนวนเงินที่รับ → ยืนยัน
   - ✅ แสดงหน้าจอ "ชำระเงินสำเร็จ" / Thank You overlay

6. บิลถูกสร้างและปิดอัตโนมัติ → ตะกร้าล้าง

### Flow สรุป

```
[Login pos1] → [POS Screen]
        ↓
[ค้นหาสินค้า / สแกนบาร์โค้ด]
        ↓
[สินค้าเข้าตะกร้า] → [ราคารวมอัปเดต]
        ↓
[กด "ชำระเงิน"] → [เลือก "เงินสด"]
        ↓
[กรอกจำนวนเงิน] → [ยืนยัน]
        ↓
[Thank You Overlay] → [ตะกร้าล้าง] → [บิลบันทึกใน DB]
```

---

## Case 2: การขายพร้อมส่วนลด (Van Staff)

**สถานการณ์**: Van Staff ให้ส่วนลดพิเศษแก่ลูกค้า

### ขั้นตอน

1. เพิ่มสินค้าลงตะกร้า (เหมือน Case 1)

2. ในส่วน "ส่วนลด" → กดปุ่ม `5%`, `10%`, `15%`, หรือ `20%`
   - หรือพิมพ์จำนวนในช่อง "ส่วนลด" แล้วเลือก `%` หรือ `฿`

3. ยอด "รวมสุทธิ" ต้องลดลงตามที่กำหนด

4. ชำระเงินตามปกติ

### Flow สรุป

```
[ตะกร้ามีสินค้า]
        ↓
[กดปุ่ม % (5/10/15/20)] หรือ [พิมพ์ตัวเลข + เลือก %/฿]
        ↓
[ยอด "รวมสุทธิ" ลดลง] ← ตรวจสอบความถูกต้อง
        ↓
[ชำระเงิน] → [บิลบันทึกส่วนลดใน DB]
```

---

## Case 3: การขายพร้อมผูกสมาชิก (Van Staff)

**สถานการณ์**: ลูกค้าเป็นสมาชิก Van Staff ต้องการบันทึกใต้ชื่อสมาชิก

### ขั้นตอน

1. เพิ่มสินค้าลงตะกร้า

2. กดช่อง **"เบอร์โทรสมาชิก"** → พิมพ์เบอร์ → กด Enter
   - ✅ ชื่อสมาชิกแสดงขึ้นมา

3. กด **"ชำระเงิน"** → เลือกวิธีชำระ → ยืนยัน

### Flow สรุป

```
[ตะกร้ามีสินค้า]
        ↓
[พิมพ์เบอร์โทรในช่อง "เบอร์โทรสมาชิก"] → Enter
        ↓
[ระบบค้นหาสมาชิก] → [ชื่อสมาชิกแสดงบนบิล]
        ↓
[ชำระเงิน] → [บิลบันทึกชื่อสมาชิกใน DB]
```

---

## Case 4: การลงทะเบียนสมาชิกใหม่ (Van Staff)

**สถานการณ์**: ลูกค้าใหม่ต้องการสมัครสมาชิก ณ จุดขาย

### ขั้นตอน

1. กดปุ่ม 👤+ (เพิ่มสมาชิก) บน Header

2. กรอก: ชื่อ, เบอร์โทร (required), อีเมล (optional)

3. กด **"บันทึก"**
   - ✅ แสดงข้อความสำเร็จ

### Flow สรุป

```
[กดปุ่ม 👤+ บน Header]
        ↓
[Dialog ลงทะเบียนสมาชิก]
        ↓
[กรอก ชื่อ + เบอร์โทร (required) + อีเมล (optional)]
        ↓
[กด "บันทึก"] → POST /members
        ↓
[สำเร็จ] → [สมาชิกใหม่บันทึกใน DB]
        ↓
[ผูกสมาชิกใหม่ในบิลได้ทันที (Case 3)]
```

---

## Case 5: การคืนสินค้า (Van Staff)

**สถานการณ์**: ลูกค้านำสินค้ากลับมาคืน Van Staff ต้องคืนเงิน

### ขั้นตอน

1. กดปุ่ม 🔴 (คืนสินค้า) บน Header

2. กรอก **บิล ID** ของบิลเดิมที่ต้องการคืน
   - ดู Bill ID ได้จากปุ่ม 🕐 (ประวัติบิล)

3. เลือกรายการที่ต้องการคืน + ระบุจำนวน

4. เลือกวิธีคืนเงิน: เงินสด หรือ เครดิต

5. กด **"ยืนยันคืนสินค้า"**
   - ✅ Credit Note ถูกสร้าง

### Flow สรุป

```
[กดปุ่ม 🔴 บน Header]
        ↓
[กรอก Bill ID] → [โหลดบิลเดิม]
        ↓
[เลือกรายการที่คืน + จำนวน]
        ↓
[เลือกวิธีคืน: เงินสด / เครดิต]
        ↓
[กด "ยืนยันคืนสินค้า"] → POST /return-notes
        ↓
[Credit Note บันทึกใน DB]
        ↓
[HQ Manager เห็นใน Backoffice → Returns]
```

---

## Case 6: การพักบิล (Van Staff)

**สถานการณ์**: กำลังขายอยู่ มีลูกค้าใหม่เข้ามา ต้องพักบิลเดิมก่อน

### ขั้นตอน

1. เพิ่มสินค้าลงตะกร้าบางส่วน

2. กดปุ่ม ⏸ (พักบิล) → กรอกชื่อ/หมายเหตุ (optional) → ยืนยัน
   - ✅ ตะกร้าล้าง พร้อมรับลูกค้าใหม่

3. ขายลูกค้าใหม่เสร็จ → กดปุ่ม ⏸ อีกครั้ง
   - ✅ เห็นรายการบิลที่พักไว้ → กดเรียกคืน

### Flow สรุป

```
[บิล A: มีสินค้าในตะกร้า]
        ↓
[กดปุ่ม ⏸] → [กรอกชื่อ/หมายเหตุ] → [ยืนยัน]
        ↓
[บิล A: สถานะ "held"] → [ตะกร้าล้าง]
        ↓
[บิล B: ขายลูกค้าใหม่] → [ชำระเงิน]
        ↓
[กดปุ่ม ⏸ อีกครั้ง] → [เลือกบิล A จากรายการ]
        ↓
[บิล A: กลับมาในตะกร้า] → [ขายต่อ]
```

---

## Case 7: Inventory Transfer — โอนสินค้า HQ → รถแวน

> ระบบรองรับ **2 Workflow** คือ HQ-initiated (7A–7D) และ Van Staff-initiated (7E–7I)

**สถานการณ์ A**: เช้าก่อนรถออก HQ เป็นฝ่ายสร้างใบโอนให้รถแวน
**สถานการณ์ B**: Van Staff ขาดของระหว่างวัน ส่งคำขอเบิกมาที่ HQ (→ ดู Case 15 ด้วย)

---

### Workflow A — HQ-initiated

#### 7A — HQ Manager สร้างใบโอน (localhost:8082)

1. Login `hqmanager / hq123456` → เข้า Backoffice อัตโนมัติ

2. ไปเมนู **Transfers** (sidebar ซ้าย)

3. กด **"+ สร้างใบโอนใหม่"**

4. กรอก:
   - ต้นทาง: เลือก Dropdown สาขา HQ
   - ปลายทาง (Van Staff): เลือก Dropdown Van Staff จากรายชื่อ
   - ค้นหารหัสสินค้า + ระบุจำนวน

5. กด **"สร้าง"**
   - ✅ ใบโอนสถานะ `pending` (ส้มอ่อน) ปรากฏในรายการ

#### 7B — Admin อนุมัติ (localhost:8081)

6. Login `admin / admin123` → Backoffice → **Transfers**

7. เห็นใบโอนสถานะ `pending` → กด **"อนุมัติ"**
   - ✅ สถานะเปลี่ยนเป็น `approved`

#### 7C — HQ จ่ายของ (Dispatch)

8. ที่ใบโอนเดิม → กด **"จัดส่ง"**
   - ✅ สถานะเปลี่ยนเป็น `dispatched`
   - ✅ สต๊อก HQ ถูกตัดออก

#### 7D — Van Staff รับของ (localhost:8083)

9. Login `pos1` → POS → กดปุ่ม 🚚 (รับสินค้าโอน)

10. เห็นใบโอนที่ส่งมาให้ สถานะ `dispatched`

11. กรอกจำนวนที่รับจริงในแต่ละรายการ

12. กด **"ยืนยันรับ"**
    - ✅ สถานะเปลี่ยนเป็น `received`
    - ✅ สต๊อกเพิ่มในรถแวน

### Flow สรุป — Workflow A

```
HQ Manager (8082)          Admin (8081)           Van Staff (8083)
─────────────────          ────────────           ────────────────
[Transfers]
[+ สร้างใบโอน]
[เลือก Van Staff + Parts]
[กด สร้าง]
        ↓
   pending 🟡
        │
        ▼
                           [Transfers]
                            [กด อนุมัติ]
                                ↓
                             approved 🔵
                                │
                                ▼
HQ Manager (8082)
[กด จัดส่ง]
[สต๊อก HQ ถูกตัด]
        ↓
   dispatched 🟣
        │
        └──────────────────────────────────────► [ปุ่ม 🚚 รับสินค้าโอน]
                                                 [เห็นใบโอน dispatched]
                                                 [กรอกจำนวนรับจริง]
                                                 [กด ยืนยันรับ]
                                                       ↓
                                                    received 🟢
                                                 [สต๊อกรถแวนเพิ่ม]

Status: pending → approved → dispatched → received
```

---

### Workflow B — Van Staff-initiated (คำขอเบิกสินค้า)

> Van Staff ขาดสินค้าระหว่างวัน ต้องการเบิกเพิ่มจาก HQ

#### 7E — Van Staff ส่งคำขอ (localhost:8083)

1. Login `pos1` → POS → กดปุ่ม 📋 (คำขอเบิกสินค้า)

2. Tab **"สร้างคำขอใหม่"**:
   - เลือกต้นทาง: Dropdown สาขา (เลือก HQ)
   - ปลายทาง: แสดงอัตโนมัติ (สาขารถของตัวเอง)
   - ค้นหาสินค้า + ระบุจำนวน
   - กรอกหมายเหตุ (optional)

3. กด **"ส่งคำขอเบิกสินค้า"**
   - ✅ คำขอสถานะ `requested` (ส้ม) ถูกสร้าง

#### 7F — HQ Manager รับเรื่อง (localhost:8082)

4. Login `hqmanager` → Backoffice → **Transfers**

5. เห็นรายการสถานะ `requested` แสดงป้าย **"คำขอเบิก"** สีส้ม

6. กด **"รับเรื่อง"**
   - ✅ สถานะเปลี่ยนเป็น `pending` → ดำเนินขั้นตอนต่อเหมือน Workflow A (7B → 7C → 7D)
   - หรือกด **"ปฏิเสธ"** → สถานะ `cancelled`

#### 7G — ติดตามสถานะจาก Van Staff

7. Van Staff กด 📋 → Tab **"คำขอของฉัน"**
   - เห็นคำขอพร้อม badge สถานะ
   - ถ้าสถานะ `dispatched` → กด **"ยืนยันรับสินค้า"** ได้ทันทีจาก Dialog นี้

### Flow สรุป — Workflow B

```
Van Staff (8083)           HQ Manager (8082)      Admin (8081)
────────────────           ─────────────────      ────────────
[📋 คำขอเบิก]
[Tab: สร้างคำขอ]
[เลือก HQ + Parts]
[กด ส่งคำขอ]
        ↓
   requested 🟠
        │
        └──────────────► [Transfers]
                          [badge: คำขอเบิก 🟠]
                          [กด รับเรื่อง]
                                ↓
                             pending 🟡
                             (→ ต่อ Workflow A: 7B–7D)
                                │
                                ▼
                                        [กด อนุมัติ]
                                              ↓
                                          approved 🔵
                                              │
                                              ▼
                          [กด จัดส่ง]
                          [สต๊อก HQ ตัด]
                                ↓
                            dispatched 🟣
                                │
        ◄─────────────────────────────────────┘
[📋 Tab: คำขอของฉัน]
[badge: dispatched 🟣]
[กด ยืนยันรับสินค้า]
        ↓
    received 🟢
[สต๊อกรถเพิ่ม]

Status: requested → pending → approved → dispatched → received
        (ยกเลิกได้ที่: requested / pending / approved)
```

---

## Case 8: นับสต๊อก (Van Staff)

**สถานการณ์**: สิ้นวัน Van Staff นับสินค้าที่เหลือในรถ

### ขั้นตอน

1. Login `pos1` → กดปุ่ม 📦 (นับสต๊อก)

2. ระบบสร้างรอบนับอัตโนมัติ → แสดงรายการสินค้าพร้อม **ยอดในระบบ**

3. นับของจริง → กรอกจำนวนในช่อง "นับจริง" ทุกรายการ

4. กด **"บันทึก"** (บันทึกชั่วคราว ยังแก้ได้)

5. เมื่อนับเสร็จทั้งหมด → กด **"ส่งยืนยัน"** → ยืนยัน

6. ✅ แสดงรายงาน Variance ทันที:
   - รายการที่นับน้อยกว่าระบบ → แสดงสีแดง
   - รายการที่นับมากกว่าระบบ → แสดงสีเขียว

### Flow สรุป

```
[กดปุ่ม 📦] → POST /stock-counts (สร้างรอบนับ)
        ↓
[ระบบ Snapshot ยอดสต๊อกจาก address_master]
        ↓
[แสดงตาราง: สินค้า | ยอดระบบ | ช่องนับจริง]
        ↓
[กรอกจำนวนนับจริง]
        ↓
[กด "บันทึก"] → PUT /stock-counts/:id/items (draft ยังแก้ได้)
        ↓
[กด "ส่งยืนยัน"] → PUT /stock-counts/:id/submit
        ↓
[status: draft → submitted]
        ↓
[GET /reports/stock-variance?countId=...]
        ↓
[แสดง Variance Report]
   ┌─────────────────────────────────┐
   │ สินค้า    ระบบ   จริง  ส่วนต่าง      │
   │ P0001    100   95    -5  🔴     │
   │ P0002    50    52    +2  🟢     │
   └─────────────────────────────────┘
        ↓
[HQ Manager ดูรายงานได้ใน Variance (Case 11)]
```

---

## Case 9: ปิดยอดประจำวัน — Daily Close (Van Staff)

**สถานการณ์**: สิ้นวัน Van Staff ปิดยอดขายก่อนนำเงินส่ง HQ

### ขั้นตอน

1. Login `pos1` → กดปุ่ม 🧮 (ปิดยอด)

2. ระบบดึงยอดขายวันนี้มาแสดง:
   - ยอดขายรวม, เงินสด, โอนเงิน, ยอดคืนสินค้า, ยอดสุทธิ

3. ตรวจสอบว่าถูกต้อง → กด **"ยืนยันปิดยอด"**

4. ✅ Daily Close ถูกสร้าง สถานะ `pending_reconciliation`

### Flow สรุป

```
[กดปุ่ม 🧮] → GET /daily-closes/summary?branchId=&posId=&date=today
        ↓
[แสดงสรุปยอดวันนี้]
   ┌──────────────────────────────┐
   │ ยอดขายรวม     ฿ 3,500.00     │
   │ เงินสด         ฿ 2,000.00     │
   │ โอนเงิน        ฿ 1,500.00     │
   │ ยอดคืนสินค้า     ฿ 200.00       │
   │ ยอดสุทธิ        ฿ 3,300.00     │
   └──────────────────────────────┘
        ↓
[กด "ยืนยันปิดยอด"] → POST /daily-closes
        ↓
[Daily Close สร้าง: status = pending_reconciliation]
        ↓
[HQ Manager เห็นใน Cash Recon (Case 10)]
```

---

## Case 10: ยืนยันรับเงิน — Cash Reconciliation (HQ Manager)

**สถานการณ์**: Van Staff นำเงินมาส่ง HQ ตรวจนับแล้วยืนยัน

### ขั้นตอน (ต่อจาก Case 9)

1. Login `hqmanager` → Backoffice → **Cash Recon**

2. Tab **"รอการยืนยัน"** → เห็นรายการ Daily Close ของรถแวน

3. กดเลือกรายการ → ด้านขวาแสดงรายละเอียด

4. นับเงินจริง → กรอก **"ยอดที่รับจริง"**

5. กรอก **"หมายเหตุ"** ถ้ามีส่วนต่าง

6. กด **"ยืนยันรับเงิน"**
   - ✅ Daily Close เปลี่ยนสถานะเป็น `reconciled`
   - ✅ รายการย้ายไปที่ Tab **"ประวัติการยืนยัน"**

### Flow สรุป

```
Van Staff (Case 9)                HQ Manager (8082)
──────────────────                ─────────────────
Daily Close
pending_reconciliation ──────────► [Cash Recon]
                                   [Tab: รอการยืนยัน]
                                   [เลือกรายการ]
                                          ↓
                                   [ฟอร์มขวา]
                                   Expected: ฿ 3,300
                                   Actual:   [กรอก]
                                   Notes:    [กรอก]
                                          ↓
                                   [กด ยืนยันรับเงิน]
                                   POST /cash-reconciliations
                                          ↓
                                   reconciled ✅
                                          ↓
                                   [Tab: ประวัติ]
                                   Expected ฿3,300 | Actual ฿3,250
                                   ส่วนต่าง: -฿50 🔴

Status: pending_reconciliation → reconciled
```

---

## Case 11: ดูรายงานส่วนต่างสต๊อก — Variance Report (HQ Manager)

**สถานการณ์**: HQ ต้องการตรวจสอบว่าสต๊อกของรถแวนต่างจากระบบเท่าไหร่

### ขั้นตอน (ต่อจาก Case 8)

1. Login `hqmanager` → Backoffice → **Variance**

2. Dropdown **"เลือกรอบนับสต๊อก"** → เลือกรอบที่ Van Staff ส่งมา

3. ✅ ตารางแสดง: ยอดระบบ | นับจริง | ส่วนต่าง

4. Summary chips บนสุด: รายการทั้งหมด, มีส่วนต่าง, ผลต่างรวม

### Flow สรุป

```
Van Staff Submit Stock Count (Case 8)
        ↓
[HQ Manager: Backoffice → Variance]
        ↓
[Dropdown: เลือกรอบนับ SC20260402000001]
        ↓
GET /reports/stock-variance?countId=SC20260402000001
        ↓
[Summary Chips]
┌──────────────────────────────────────────────────┐
│ สาขา: 00000 | รายการทั้งหมด: 10 | มีส่วนต่าง: 2       │
│ ผลต่างรวม: -3                                     │
└──────────────────────────────────────────────────┘
        ↓
[ตาราง]
┌──────────────────────────────────────────────────┐
│ รหัส  ชื่อสินค้า    ยอดระบบ  นับจริง  ส่วนต่าง            │
│ P0001 Sample 01    100      95       -5  🔴      │
│ P0002 Sample 02     50      52       +2  🟢      │
│ P0003 Sample 03     75      75        0          │
└──────────────────────────────────────────────────┘
```

---

## Case 12: Support POS Monitor (Admin เท่านั้น)

**สถานการณ์**: Admin ต้องการดูหน้าจอ Van Staff แบบ Real-time เมื่อมีปัญหา

### ขั้นตอน

1. Login `pos1` → POS (ต้องเปิดไว้)

2. Login `admin` → Backoffice → **Support POS**

3. แผงซ้าย: เห็น **"Online (1)"** → `Van Staff 1` มีจุดเขียว

4. กดชื่อ `Van Staff 1` → แผงขวา POSMirrorView แสดง

5. Van Staff เพิ่มสินค้า → Admin เห็น Real-time ภายใน ~1 วินาที

6. ✅ ทุกปุ่มใน POSMirrorView กดไม่ได้ (View Only)

### Flow สรุป

```
Van Staff (8083)                        Admin (8081)
────────────────                        ────────────
[POS เปิดอยู่]
[WebSocket เชื่อมต่อ]                      [Support POS]
[Broadcaster]          ─── WS ───►      [Watcher]
                                        [Online: Van Staff 1 🟢]
                                               ↓
[เพิ่มสินค้าลงตะกร้า]                       [กดชื่อ Van Staff 1]
        ↓                                      ↓
[BillProvider notify]               [ส่ง {"type":"watch",...}]
        ↓                                      ↓
[pos_state JSON]  ──── Go Hub ────► [POSMirrorView อัปเดต]
(debounce 300ms)                    [AbsorbPointer: กดไม่ได้]

Go Hub:
  broadcaster map  ──►  watcher map
  stateCache[vanID] = latestJSON
```

---

## Case 13: Role-Based Access Control

**สถานการณ์**: ตรวจสอบว่า role แต่ละ role เข้าถึงแค่สิ่งที่ควรเข้าถึง

### ขั้นตอน

#### 13A — Admin ไม่เห็น POS
1. Login `admin` → ✅ เข้า Backoffice โดยตรง
2. Avatar menu → ✅ มีแค่ "ออกจากระบบ"

#### 13B — HQ Manager ไม่เห็น ORGANIZATION
3. Login `hqmanager` → Sidebar ✅ ไม่มี Users, Company, Branches, POS, Support POS

#### 13C — Van Staff ไม่มี Backoffice
4. Login `pos1` → ✅ เข้า POS / ไม่มีปุ่ม OFFICE

#### 13D — API Authorization
5. DevTools (F12) → Network → Login `pos1`
6. GET `/users` → ✅ 403 Forbidden

### Flow สรุป

```
Login
  ↓
AuthGate
  ├── isCustomerDisplay? ──► CustomerScreen
  ├── hasBackofficeAccess?
  │     ├── isSuperAdmin ──► BackofficeScreen (ทุกหน้า)
  │     └── isHQManager  ──► BackofficeScreen (ซ่อน ORGANIZATION + SUPPORT)
  └── else (Van Staff) ───► HomeScreen / POS

URL Guard:
  HomeScreen.initState
    └── hasBackofficeAccess? → pushAndRemoveUntil BackofficeScreen

API Guard (Backend):
  RequirePermission middleware
    └── role ไม่มี permission → 403 Forbidden
```

---

## Case 14: QR Payment (Van Staff)

**สถานการณ์**: ลูกค้าต้องการชำระด้วย QR Code

### ขั้นตอน

1. Admin → Backoffice → **Payment** → Upload รูป QR Code

2. Van Staff → เพิ่มสินค้า → กด **"ชำระเงิน"**

3. เลือก **QR / โอนเงิน** → ✅ แสดง QR Code

4. กด **"ยืนยันรับเงิน"** หลังลูกค้าโอนเสร็จ

### Flow สรุป

```
[Admin: Payment → Upload QR Image]
        ↓
[Van Staff: ตะกร้ามีสินค้า]
        ↓
[กด "ชำระเงิน"] → [เลือก "QR / โอนเงิน"]
        ↓
[GET /assets/qr-image] → [แสดง QR Code บนหน้าจอ]
        ↓
[ลูกค้าสแกนและโอนเงิน]
        ↓
[Van Staff กด "ยืนยันรับเงิน"]
        ↓
[บิลปิด: payment_method = transfer]
```

---

## Case 15: คำขอเบิกสินค้า (Van Staff)

**สถานการณ์**: Van Staff ขาดสินค้าระหว่างวัน ต้องการเบิกเพิ่มจาก HQ โดยไม่ต้องโทรหา

### ขั้นตอน

1. Login `pos1` → POS → กดปุ่ม 📋 (คำขอเบิกสินค้า) บน Header

2. **Tab "คำขอของฉัน"** — ดูรายการคำขอที่เคยส่ง
   - badge สี: 🟠 รอรับเรื่อง → 🟡 รออนุมัติ → 🔵 อนุมัติแล้ว → 🟣 จัดส่งแล้ว → 🟢 รับแล้ว
   - ถ้า `requested` → ปุ่ม **"ยกเลิกคำขอ"**
   - ถ้า `dispatched` → ปุ่ม **"ยืนยันรับสินค้า"**

3. **Tab "สร้างคำขอใหม่"** — กรอกคำขอ
   - เลือกสาขาต้นทาง (HQ ที่จะเบิกจาก)
   - ปลายทางแสดงอัตโนมัติ (รถของตัวเอง)
   - พิมพ์ค้นหาสินค้า → เลือก → ระบุจำนวน
   - เพิ่มรายการได้หลายรายการ
   - กรอกหมายเหตุ (optional)

4. กด **"ส่งคำขอเบิกสินค้า"**
   - ✅ Dialog ปิด + SnackBar "ส่งคำขอสำเร็จ"
   - ✅ HQ Manager เห็นรายการใหม่ใน Transfers หน้า Backoffice ทันที

5. HQ Manager → กด **"รับเรื่อง"** → Admin อนุมัติ → HQ จัดส่ง → Van Staff กดรับในTab "คำขอของฉัน"

### Flow สรุป

```
[Van Staff: กดปุ่ม 📋]
        ↓
[Dialog: 2 Tabs]
  ├── Tab "คำขอของฉัน"
  │     └── [รายการพร้อม badge สถานะ]
  │               ├── requested → [ปุ่มยกเลิก]
  │               └── dispatched → [ปุ่มยืนยันรับสินค้า]
  │
  └── Tab "สร้างคำขอใหม่"
        ↓
[เลือก HQ ต้นทาง]
[ค้นหาสินค้า + จำนวน]
[กด ส่งคำขอ]
        ↓
POST /transfers (status = requested)
        ↓
[HQ Manager: Transfers → badge คำขอเบิก 🟠]
[กด รับเรื่อง] → status: pending
        ↓
[ดำเนิน Workflow ปกติ: อนุมัติ → จัดส่ง → รับ]
```

---

## Flow สรุปทั้งระบบ (วงจรประจำวัน)

```
┌──────────────────────────────────────────────────────────────────────┐
│                    วงจรการทำงานประจำวัน                               │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  เช้า (ก่อนรถออก)                                                      │
│  ─────────────────                                                   │
│  HQ Manager                                                          │
│    [Transfers] สร้างใบโอนสินค้าให้รถแวน → pending                        │
│         ↓                                                            │
│  Admin                                                               │
│    [Transfers] อนุมัติ → approved → กด จัดส่ง → dispatched → ตัดสต๊อก HQ    │
│         ↓                                                            │
│  Van Staff                                                           │
│    [รับสินค้าโอน 🚚] ยืนยันรับของ → received → บวกสต๊อกรถ                   │
│                                                                      │
│  ระหว่างวัน (รถออกวิ่ง)                                                  │
│  ─────────────────────                                               │
│  Van Staff                                                           │
│    [POS] สแกนสินค้า → เพิ่มตะกร้า → ชำระเงิน (สด/QR)                       │
│    [POS] ผูกสมาชิก / ให้ส่วนลด / พักบิล / คืนสินค้า                           │
│    [📋 คำขอเบิก] ถ้าของหมดกลางวัน → ส่งคำขอ → HQ รับเรื่อง → รับของ          │
│    (Admin สามารถ Monitor แบบ Real-time ผ่าน Support POS)              │
│                                                                      │
│  เย็น (รถกลับ HQ)                                                      │
│  ──────────────────                                                  │
│  Van Staff                                                           │
│    [นับสต๊อก 📦] นับของในรถ → ส่งยืนยัน → Variance Report                  │
│    [ปิดยอด 🧮]  ปิดยอดขาย → pending_reconciliation                     │
│         ↓                                                            │
│  HQ Manager                                                          │
│    [Variance] ดูรายงานส่วนต่างสต๊อก                                      │
│    [Cash Recon] รับเงินจากรถ → ยืนยัน → reconciled                       │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘

Status Transitions:
  Transfer (HQ-initiated):          pending → approved → dispatched → received
  Transfer (Van Staff-initiated):   requested → pending → approved → dispatched → received
  Transfer (ยกเลิกได้ที่):           requested / pending / approved → cancelled
  DailyClose:                       (created) → pending_reconciliation → reconciled
  StockCount:                       draft → submitted
```

---

## Checklist การทดสอบ

กาเครื่องหมายที่ช่อง `[✔]` เมื่อทดสอบแล้วผ่าน หรือ `[✖]` ถ้า error

### Case 1: ขายสินค้าพื้นฐาน
- [] Login pos1 → เข้า POS โดยตรง (ไม่ใช่ Backoffice)
- [] ค้นหาสินค้าแล้วเพิ่มลงตะกร้าได้
- [] ราคารวมคำนวณถูกต้อง
- [] กดชำระเงิน → เลือกเงินสด → ยืนยันสำเร็จ
- [] หน้าจอ Thank You แสดงขึ้นมา
- [] ตะกร้าล้างหลังชำระ

### Case 2: ขายพร้อมส่วนลด
- [] กดปุ่มเปอร์เซ็นต์ (5%/10%/15%/20%) แล้วยอดลดลงถูกต้อง
- [] พิมพ์ส่วนลดเองแล้วยอดลดลงถูกต้อง
- [] สลับโหมด % กับ ฿ ได้
- [] ชำระเงินพร้อมส่วนลดสำเร็จ

### Case 3: ขายพร้อมผูกสมาชิก
- [] พิมพ์เบอร์โทรสมาชิกแล้วชื่อแสดงขึ้น
- [] ชำระเงินพร้อมสมาชิกสำเร็จ
- [] ใบเสร็จต้องแสดงชื่อสมาชิก

### Case 4: ลงทะเบียนสมาชิกใหม่
- [] กดปุ่ม 👤+ บน Header
- [] กรอกข้อมูลและบันทึกสำเร็จ
- [] ค้นหาสมาชิกใหม่ด้วยเบอร์โทรได้

### Case 5: คืนสินค้า
- [] กดปุ่ม 🔴 บน Header
- [] กรอก Bill ID และโหลดบิลเดิมได้
- [] เลือกรายการและจำนวนที่คืน
- [] ยืนยันคืนสินค้าสำเร็จ
- [] ไม่ใส่สมาชิก เก็บเครดิตคืนไม่ได้
- [] Credit Note ปรากฏในหน้า Returns ของ HQ Manager

### Case 6: พักบิล
- [] เพิ่มสินค้า → กด ⏸ → พักบิลได้
- [] ตะกร้าล้างหลังพัก
- [] เรียกบิลที่พักกลับมาได้
- [] ลบบิลที่พักได้

### Case 7: Inventory Transfer — Workflow A (HQ-initiated)
- [] 7A: HQ Manager สร้างใบโอนได้ → สถานะ `pending` (เลือก Van Staff จาก Dropdown ได้)
- [] 7B: Admin อนุมัติได้ → สถานะ `approved`
- [] 7C: HQ กด จัดส่ง ได้ → สถานะ `dispatched`
- [] 7D: Van Staff เห็นใบโอนที่ปุ่ม 🚚
- [] 7D: Van Staff กรอกจำนวนรับและยืนยันได้ → สถานะ `received`

### Case 7: Inventory Transfer — Workflow B (Van Staff-initiated)
- [] 7E: Van Staff กดปุ่ม 📋 → Dialog เปิดได้
- [] 7E: Van Staff ส่งคำขอเบิกได้ → สถานะ `requested` (สีส้ม)
- [] 7F: HQ Manager เห็นรายการ badge "คำขอเบิก" สีส้มใน Transfers
- [] 7F: HQ Manager กด "รับเรื่อง" → สถานะเปลี่ยนเป็น `pending`
- [] 7F: HQ Manager กด "ปฏิเสธ" → สถานะเปลี่ยนเป็น `cancelled`
- [] 7G: Van Staff Tab "คำขอของฉัน" แสดง badge ตามสถานะได้
- [] 7G: Van Staff กด "ยืนยันรับสินค้า" ใน Tab ได้ → สถานะ `received`

### Case 8: นับสต๊อก
- [] กดปุ่ม 📦 เปิด Dialog นับสต๊อกได้
- [] รายการสินค้าพร้อมยอดระบบแสดงขึ้น
- [] กรอกจำนวนนับจริงได้
- [] บันทึกชั่วคราวสำเร็จ
- [] ส่งยืนยันสำเร็จ
- [] Variance Report แสดงหลัง Submit (สีแดง=ขาด, สีเขียว=เกิน)

### Case 9: ปิดยอดประจำวัน
- [] กดปุ่ม 🧮 เปิด Dialog ปิดยอดได้
- [] ยอดขายวันนี้แสดงถูกต้อง (ต้องมีบิลจาก Case 1 ก่อน)
- [] ยืนยันปิดยอดสำเร็จ

### Case 10: Cash Reconciliation
- [] HQ Manager เปิด Cash Recon → Tab "รอการยืนยัน" มีรายการ
- [] กดเลือกรายการ → ฟอร์มแสดงทางขวา
- [] กรอกยอดที่รับจริง → ยืนยันสำเร็จ
- [] รายการย้ายไป Tab "ประวัติการยืนยัน"
- [] แสดงส่วนต่าง Expected vs Actual

### Case 11: Variance Report
- [] HQ Manager เปิด Variance → มี Dropdown รอบนับ
- [] เลือกรอบนับแล้วตารางแสดง
- [] Summary chips แสดงถูกต้อง
- [] แถวสีแดง = ขาด, สีเขียว = เกิน

### Case 12: Support POS Monitor
- [] pos1 เปิด POS อยู่ (ต้อง Online)
- [] Admin → Support POS → เห็น "Online (1)"
- [] กดชื่อ Van Staff → POSMirrorView แสดง
- [] Van Staff เพิ่มสินค้า → Admin เห็นใน ~1 วินาที
- [] ทุกปุ่มใน POSMirrorView กดไม่ได้

### Case 13: Role-Based Access Control
- [] 13A: Admin เข้า Backoffice โดยตรง / ไม่มีปุ่ม "POS" ใน menu
- [] 13B: HQ Manager ไม่เห็น Users, Company, Branches, POS, Support POS
- [] 13C: Van Staff เข้า POS โดยตรง / ไม่มีปุ่ม OFFICE
- [] 13D: pos1 เรียก GET /users → ได้ 403

### Case 14: QR Payment
- [] Admin ตั้งค่า QR Image ได้
- [] Van Staff ชำระด้วย QR → แสดง QR Code
- [] ยืนยันรับเงินสำเร็จ

### Case 15: คำขอเบิกสินค้า (Van Staff)
- [] ปุ่ม 📋 "คำขอเบิกสินค้า" ปรากฏบน Header ของ Van Staff
- [] Dialog เปิดได้ มี 2 Tabs: "คำขอของฉัน" และ "สร้างคำขอใหม่"
- [] Tab "สร้างคำขอใหม่": Dropdown สาขาต้นทางโหลดได้
- [] Tab "สร้างคำขอใหม่": ช่องค้นหาสินค้าทำงานได้ (พิมพ์ชื่อ/รหัส → มี Suggestion)
- [] Tab "สร้างคำขอใหม่": เพิ่มหลายรายการสินค้าได้ (ปุ่ม "เพิ่มรายการ")
- [] กด "ส่งคำขอเบิกสินค้า" → สำเร็จ + Dialog ปิด
- [] HQ Manager: Transfers page แสดงคำขอใหม่ badge "คำขอเบิก" สีส้ม
- [] HQ Manager: กด "รับเรื่อง" → สถานะเปลี่ยนเป็น `pending`
- [] Tab "คำขอของฉัน": แสดงรายการพร้อม badge สถานะถูกต้อง
- [] Tab "คำขอของฉัน" status `requested`: ปุ่ม "ยกเลิกคำขอ" ทำงานได้
- [] Tab "คำขอของฉัน" status `dispatched`: ปุ่ม "ยืนยันรับสินค้า" ทำงานได้ → สถานะ `received`

---

*อัปเดตล่าสุด: 2026-04-02*
