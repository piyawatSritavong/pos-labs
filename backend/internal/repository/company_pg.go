package repository

import (
	"context"
	"database/sql"
	"errors"
)

type companyRepositoryPG struct {
	db *sql.DB
}

func NewCompanyRepository(db *sql.DB) CompanyRepository {
	return &companyRepositoryPG{db: db}
}

func (r *companyRepositoryPG) Get(ctx context.Context) (*Company, error) {
	// COALESCE on receipt_footer guards against legacy rows that pre-date the
	// 0010_receipt_customization migration (which set a DEFAULT '' for new rows
	// but leaves NULL on rows existing before the column was added).
	row := r.db.QueryRowContext(ctx, `
		SELECT "tax_id", "company_name", "company_name_th", "company_address", "company_address_th",
		       "phone", "email", "website", "logo_url", "tax_rate", "tax_type",
		       COALESCE("receipt_footer", '')
		FROM "company_setting"
		LIMIT 1
	`)

	var c Company
	var email, website, logoURL sql.NullString
	err := row.Scan(
		&c.TaxID, &c.CompanyName, &c.CompanyNameTH, &c.CompanyAddress, &c.CompanyAddressTH,
		&c.Phone, &email, &website, &logoURL, &c.TaxRate, &c.TaxType,
		&c.ReceiptFooter,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	if email.Valid {
		c.Email = &email.String
	}
	if website.Valid {
		c.Website = &website.String
	}
	if logoURL.Valid {
		c.LogoURL = &logoURL.String
	}

	return &c, nil
}

func (r *companyRepositoryPG) Update(ctx context.Context, company *Company) error {
	_, err := r.db.ExecContext(ctx, `
		UPDATE "company_setting"
		SET "company_name" = $1, "company_name_th" = $2, "company_address" = $3, "company_address_th" = $4,
		    "phone" = $5, "email" = $6, "website" = $7, "logo_url" = $8, "tax_rate" = $9, "tax_type" = $10,
		    "receipt_footer" = $11
		WHERE "tax_id" = $12
	`,
		company.CompanyName, company.CompanyNameTH, company.CompanyAddress, company.CompanyAddressTH,
		company.Phone, company.Email, company.Website, company.LogoURL, company.TaxRate, company.TaxType,
		company.ReceiptFooter,
		company.TaxID,
	)
	return err
}
