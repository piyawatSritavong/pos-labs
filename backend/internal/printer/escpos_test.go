package printer

import (
	"bytes"
	"testing"
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
