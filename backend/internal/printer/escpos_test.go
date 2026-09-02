package printer

import (
	"bytes"
	"testing"
	"time"
)

func TestBuildReceiptASCIIModeEmitsReadableASCIIOnly(t *testing.T) {
	data := BuildReceipt(ReceiptParams{
		CompanyNameTh:   "ร้านทดสอบ",
		CompanyAddrTh:   "123 ถนนสุขุมวิท",
		ReceiptFooter:   "ขอบคุณ",
		BillID:          "BILL-001",
		CashierName:     "cashier1",
		PaymentMethod:   "Cash",
		Items:           []ReceiptItem{{Code: "P0001", Name: "สินค้าไทย", Qty: 2, UnitPrice: 15, LineTotal: 30}},
		Subtotal:        30,
		Discount:        0,
		AmountAfterDisc: 30,
		TaxRatePercent:  7,
		Tax:             1.96,
		Total:           30,
		ReceivedAmount:  100,
		ChangeAmount:    70,
		HasReceived:     true,
		HasChange:       true,
		PrintMode:       ModeASCII,
	})

	for i, b := range data {
		if b > 0x7F {
			t.Fatalf("byte %d is non-ASCII: 0x%X", i, b)
		}
	}
	for _, want := range [][]byte{
		[]byte("RECEIPT"),
		[]byte("BILL-001"),
		[]byte("ITEM P0001"),
		[]byte("Received"),
		[]byte("Change"),
	} {
		if !bytes.Contains(data, want) {
			t.Fatalf("receipt missing %q in %q", string(want), string(data))
		}
	}
}

func TestBuildReceiptASCIIModeDoesNotPrintPartialThaiNames(t *testing.T) {
	data := BuildReceipt(ReceiptParams{
		BillID:        "BILL-ASCII",
		PaymentMethod: "Cash",
		Items: []ReceiptItem{
			{Code: "PLY010C", Name: "ไม้อัดยาง 10 มิล เกรด C", Qty: 1, UnitPrice: 1, LineTotal: 1},
			{Code: "PLY020", Name: "ไม้อัดยาง 20 มิล ตราภูเขา", Qty: 1, UnitPrice: 1, LineTotal: 1},
		},
		Subtotal:        2,
		AmountAfterDisc: 2,
		Total:           2,
		PrintMode:       ModeASCII,
	})

	for _, bad := range [][]byte{[]byte("10 C"), []byte("\n20\n")} {
		if bytes.Contains(data, bad) {
			t.Fatalf("ASCII fallback leaked partial Thai item name %q in %q", string(bad), string(data))
		}
	}
	for _, want := range [][]byte{[]byte("ITEM PLY010C"), []byte("ITEM PLY020")} {
		if !bytes.Contains(data, want) {
			t.Fatalf("ASCII fallback missing %q in %q", string(want), string(data))
		}
	}
}

func TestEncodeCP874AndThaiReceiptMode(t *testing.T) {
	encoded := EncodeCP874("ก")
	if len(encoded) != 1 || encoded[0] != 0xA1 {
		t.Fatalf("EncodeCP874(ก) = %#v, want []byte{0xA1}", encoded)
	}

	data := BuildReceipt(ReceiptParams{
		CompanyNameTh:   "ก",
		BillID:          "BILL-TH",
		PaymentMethod:   "เงินสด",
		Items:           []ReceiptItem{{Code: "P0001", Name: "ไม้อัดยาง 10 มิล เกรด C", Qty: 1, UnitPrice: 1, LineTotal: 1}},
		Subtotal:        1,
		AmountAfterDisc: 1,
		Total:           1,
		PrintMode:       ModeThaiCP874,
		CodeTable:       21,
	})

	if !bytes.Contains(data, []byte{0x1B, 0x74, 0x15}) {
		t.Fatalf("Thai receipt did not select ESC t 21: %#v", data[:min(len(data), 16)])
	}
	if !bytes.Contains(data, []byte{0xA1}) {
		t.Fatalf("Thai receipt missing CP874 Thai byte 0xA1")
	}
	if !bytes.Contains(data, EncodeCP874("ไม้อัดยาง")) {
		t.Fatalf("Thai receipt missing CP874 item name bytes")
	}
}

func TestParseDrawerKickCommand(t *testing.T) {
	data, normalized, err := ParseDrawerKickCommand("0x1b 0x70 0x01 0x32 0xfa")
	if err != nil {
		t.Fatalf("ParseDrawerKickCommand returned error: %v", err)
	}
	if normalized != "1B700132FA" {
		t.Fatalf("normalized command = %q, want 1B700132FA", normalized)
	}
	if !bytes.Equal(data, []byte{0x1B, 0x70, 0x01, 0x32, 0xFA}) {
		t.Fatalf("data = %#v", data)
	}

	if _, _, err := ParseDrawerKickCommand("XYZ"); err == nil {
		t.Fatal("invalid drawer command should return an error")
	}
}

func TestBuildReceiptUsesConfiguredDrawerKick(t *testing.T) {
	command := []byte{0x1B, 0x70, 0x01, 0x32, 0xFA}
	data := BuildReceipt(ReceiptParams{
		BillID:          "BILL-DRAWER",
		Items:           []ReceiptItem{{Code: "P0001", Name: "Item", Qty: 1, UnitPrice: 1, LineTotal: 1}},
		Subtotal:        1,
		AmountAfterDisc: 1,
		Total:           1,
		PrintMode:       ModeASCII,
		OpenDrawer:      true,
		DrawerKick:      command,
	})

	if !bytes.Contains(data, command) {
		t.Fatalf("receipt missing configured drawer command %#v", command)
	}
}

// The receipt has to read like the slip the shop already hands out, so the
// layout is asserted rather than eyeballed on a roll of paper.
func TestReceiptFollowsShopSlipLayout(t *testing.T) {
	received := 1000.0
	params := ReceiptParams{
		CompanyNameTh: "หจก.บุญมาฟาร์ม โพนทอง",
		BusinessHours: "เปิดทุกวัน 05.00-20.00น.",
		Phone:         "0926663728",
		BillID:        "20260817000003",
		POSID:         "POS003",
		CashierName:   "นุ่น",
		CustomerName:  "",
		IssuedAt:      time.Date(2026, 8, 16, 11, 41, 0, 0, time.UTC),
		PaymentMethod: "เงินสด",
		Items: []ReceiptItem{
			{Code: "P0158", Name: "สีสเปย์", Qty: 24, UnitPrice: 40, LineTotal: 960},
		},
		Subtotal:       1000,
		MemberDiscount: 0,
		Discount:       30,
		Rounding:       -0.09,
		Total:          969.91,
		ReceivedAmount: received,
		ChangeAmount:   received - 969.91,
		HasReceived:    true,
		HasChange:      true,
		PrintMode:      ModeThaiCP874,
	}

	got := BuildReceipt(params)

	for _, want := range []string{
		"หจก.บุญมาฟาร์ม โพนทอง",
		"เปิดทุกวัน 05.00-20.00น. 0926663728",
		"ใบเสร็จรับเงิน/ใบกำกับภาษีอย่างย่อ",
		"เลขที่ใบ", "20260817000003",
		"เครื่อง:", "POS003",
		"พนักงาน:", "นุ่น",
		// No member on the bill still prints a customer line.
		"ลูกค้า:", "General Customer",
		"สินค้า", "จำนวน", "ราคา", "รวม",
		"ราคารวม", "ส่วนลดสมาชิก", "ส่วนลด", "ปัดเศษ",
		"รวมยอดสุทธิ", "ประเภทการชำระเงิน", "รับเงิน", "ทอนเงิน",
	} {
		if !bytes.Contains(got, EncodeCP874(want)) {
			t.Errorf("receipt is missing %q", want)
		}
	}

	// Buddhist era, day first — 16/08/2569, not 16/08/2026.
	if !bytes.Contains(got, EncodeCP874("16/08/2569")) {
		t.Error("date should be Buddhist era and day first")
	}
}

func TestReceiptOmitsCashLinesWhenNoCashChangedHands(t *testing.T) {
	params := ReceiptParams{
		CompanyNameTh: "ร้านทดสอบ",
		BillID:        "20260817000004",
		PaymentMethod: "โอน",
		Items:         []ReceiptItem{{Code: "P1", Name: "ของ", Qty: 1, UnitPrice: 10, LineTotal: 10}},
		Subtotal:      10,
		Total:         10,
		PrintMode:     ModeThaiCP874,
	}
	got := BuildReceipt(params)
	// Printing "รับเงิน 0.00" on a transfer reads as a mistake. The title
	// "ใบเสร็จรับเงิน…" contains the same word, so count rather than search.
	if n := bytes.Count(got, EncodeCP874("รับเงิน")); n != 1 {
		t.Errorf("expected 'รับเงิน' only in the title, found %d occurrences", n)
	}
	if bytes.Contains(got, EncodeCP874("ทอนเงิน")) {
		t.Error("a non-cash sale must not print a change line")
	}
	// Rounding of zero is not a fact worth a line either.
	if bytes.Contains(got, EncodeCP874("ปัดเศษ")) {
		t.Error("zero rounding should not print a line")
	}
}

// The van gives lines away; a 0.00 in the total column reads as a mistake on a
// paper slip, so the giveaway is named.
func TestReceiptNamesAGiveawayInsteadOfPrintingZero(t *testing.T) {
	params := ReceiptParams{
		CompanyNameTh: "ร้านทดสอบ",
		BillID:        "20260831000009",
		PaymentMethod: "เงินสด",
		Items: []ReceiptItem{
			{Code: "P1", Name: "ข้องอ 2 นิ้ว", Qty: 2, UnitPrice: 20, LineTotal: 40},
			{Code: "P2", Name: "เสื้อฝนลายจุด", Qty: 1, UnitPrice: 0, LineTotal: 0},
		},
		Subtotal:  40,
		Total:     40,
		PrintMode: ModeThaiCP874,
	}

	got := BuildReceipt(params)
	if !bytes.Contains(got, EncodeCP874("แถม")) {
		t.Error("a line priced at zero should print แถม")
	}
	if !bytes.Contains(got, EncodeCP874("40.00")) {
		t.Error("the paid line should still print its total")
	}
}
