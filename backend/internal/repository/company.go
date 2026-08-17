package repository

import (
	"context"
)

type Company struct {
	TaxID            string
	CompanyName      string
	CompanyNameTH    string
	CompanyAddress   string
	CompanyAddressTH string
	Phone            string
	Email            *string
	Website          *string
	LogoURL          *string
	TaxRate          float64
	TaxType          string
	// ReceiptFooter is the customizable trailing text printed at the bottom
	// of every POS receipt (added by migration 0010).
	ReceiptFooter string
	// BusinessHours prints under the shop name, e.g. "เปิดทุกวัน 05.00-20.00น."
	BusinessHours string
	// MemberDiscountRate is the fraction taken off a bill that has a member
	// attached. 0 leaves the receipt line off entirely.
	MemberDiscountRate float64
	// RoundToWholeBaht rounds the payable total, with the difference shown on
	// its own receipt line.
	RoundToWholeBaht bool
}

type CompanyRepository interface {
	Get(ctx context.Context) (*Company, error)
	Update(ctx context.Context, company *Company) error
}
