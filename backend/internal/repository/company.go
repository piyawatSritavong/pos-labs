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
}

type CompanyRepository interface {
	Get(ctx context.Context) (*Company, error)
	Update(ctx context.Context, company *Company) error
}

