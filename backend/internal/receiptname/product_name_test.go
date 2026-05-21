package receiptname

import "testing"

func TestSafeProductNameUsesReceiptName(t *testing.T) {
	name := SafeProductName(Product{
		Code:        "P0019",
		ReceiptName: "Plywood 10mm C",
		NameTH:      "ไม้อัดยาง 10 มิล เกรด C",
	})
	if name != "PLYWOOD 10MM C" {
		t.Fatalf("name = %q", name)
	}
}

func TestSafeProductNameAcceptsSeededReceiptNames(t *testing.T) {
	tests := []struct {
		nameTH string
		want   string
	}{
		{"ไม้อัดยาง 10 มิล เกรด C", "PLYWOOD 10MM C"},
		{"ไม้อัดยาง 20 มิล ตราภูเขา", "PLYWOOD 20MM PHUKHAO"},
		{"MDF 18 มิล", "MDF 18MM"},
		{"เมลามีนขาว 1 หน้า ขนาด 6 มิล", "MELAMINE WHITE 1S 6MM"},
	}
	for _, tt := range tests {
		if got := SafeProductName(Product{Code: "P0001", ReceiptName: tt.want, NameTH: tt.nameTH}); got != tt.want {
			t.Fatalf("SafeProductName(%q) = %q, want %q", tt.nameTH, got, tt.want)
		}
	}
}

func TestSafeProductNameAvoidsPartialThaiASCII(t *testing.T) {
	tests := []struct {
		code string
		name string
		want string
	}{
		{"PLY010C", "ไม้อัดยาง 10 มิล เกรด C", "PLY010C 10MM C"},
		{"PLY020", "ไม้อัดยาง 20 มิล ตราภูเขา", "PLY020 20MM PHUKHAO"},
		{"P0040", "เมลามีนขาว 1 หน้า ขนาด 6 มิล", "P0040 6MM WHITE 1S"},
		{"P9999", "สินค้าไทยล้วน", "ITEM P9999"},
	}
	for _, tt := range tests {
		got := SafeProductName(Product{Code: tt.code, NameTH: tt.name})
		if got != tt.want {
			t.Fatalf("SafeProductName(%q) = %q, want %q", tt.name, got, tt.want)
		}
		if got == "10 C" || got == "20" || got == "1 6" {
			t.Fatalf("unsafe partial name leaked: %q", got)
		}
	}
}

func TestSafeProductNameRejectsWeakReceiptName(t *testing.T) {
	got := SafeProductName(Product{
		Code:        "P0019",
		ReceiptName: "10 C",
		NameTH:      "ไม้อัดยาง 10 มิล เกรด C",
	})
	if got != "P0019 10MM C" {
		t.Fatalf("got %q, want code/traits fallback", got)
	}
}
