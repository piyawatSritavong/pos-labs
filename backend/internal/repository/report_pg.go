package repository

import (
	"context"
	"database/sql"
	"time"
)

type reportRepositoryPG struct {
	db *sql.DB
}

func NewReportRepository(db *sql.DB) ReportRepository {
	return &reportRepositoryPG{db: db}
}

func (r *reportRepositoryPG) GetBillsByDate(ctx context.Context, date time.Time) ([]Bill, error) {
	dateStart := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, time.UTC)
	return r.GetBillsByDateRange(ctx, dateStart, dateStart.Add(24*time.Hour))
}

func (r *reportRepositoryPG) GetBillsByDateRange(ctx context.Context, dateStart, dateEnd time.Time) ([]Bill, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT 
			"id", "branch_id", "pos_id", "status", "payment_method", "payment_ref",
			"member_id", "customer_name",
			"purchase_amount", "total_discount", "total_amount",
			"vat_amount", "xvat_amount",
			"created_at", "updated_at", "created_by", "updated_by"
		FROM "bill_master"
		WHERE "created_at" >= $1 AND "created_at" < $2
		ORDER BY "created_at" ASC
	`, dateStart, dateEnd)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var bills []Bill
	for rows.Next() {
		var b Bill
		var paymentMethod, paymentRef, memberID, createdBy, updatedBy sql.NullString

		err := rows.Scan(
			&b.ID,
			&b.BranchID,
			&b.POSID,
			&b.Status,
			&paymentMethod,
			&paymentRef,
			&memberID,
			&b.CustomerName,
			&b.PurchaseAmount,
			&b.TotalDiscount,
			&b.TotalAmount,
			&b.VATAmount,
			&b.XVATAmount,
			&b.CreatedAt,
			&b.UpdatedAt,
			&createdBy,
			&updatedBy,
		)
		if err != nil {
			return nil, err
		}

		if paymentMethod.Valid {
			b.PaymentMethod = paymentMethod.String
		}
		if paymentRef.Valid {
			b.PaymentRef = paymentRef.String
		}
		if memberID.Valid {
			b.MemberID = memberID.String
		}
		if createdBy.Valid {
			b.CreatedBy = createdBy.String
		}
		if updatedBy.Valid {
			b.UpdatedBy = updatedBy.String
		}

		bills = append(bills, b)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return bills, nil
}

func (r *reportRepositoryPG) GetBillsWithItemsByDate(ctx context.Context, date time.Time) ([]BillWithItems, error) {
	dateStart := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, time.UTC)
	return r.GetBillsWithItemsByDateRange(ctx, dateStart, dateStart.Add(24*time.Hour))
}

func (r *reportRepositoryPG) GetBillsWithItemsByDateRange(ctx context.Context, dateStart, dateEnd time.Time) ([]BillWithItems, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT 
			b."id", b."branch_id", b."pos_id", b."status", b."payment_method", b."payment_ref",
			b."member_id", b."customer_name",
			b."purchase_amount", b."total_discount", b."total_amount",
			b."vat_amount", b."xvat_amount",
			b."created_at", b."updated_at", b."created_by", b."updated_by",
			d."part_code", d."address_code", d."name", d."price", d."qty"
		FROM "bill_master" b
		INNER JOIN "bill_item_detail" d ON d."bill_id" = b."id"
		WHERE b."created_at" >= $1 AND b."created_at" < $2
		ORDER BY b."created_at" ASC, d."part_code" ASC
	`, dateStart, dateEnd)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []BillWithItems
	for rows.Next() {
		var bi BillWithItems
		var paymentMethod, paymentRef, memberID, createdBy, updatedBy sql.NullString

		err := rows.Scan(
			&bi.ID,
			&bi.BranchID,
			&bi.POSID,
			&bi.Status,
			&paymentMethod,
			&paymentRef,
			&memberID,
			&bi.CustomerName,
			&bi.PurchaseAmount,
			&bi.TotalDiscount,
			&bi.TotalAmount,
			&bi.VATAmount,
			&bi.XVATAmount,
			&bi.CreatedAt,
			&bi.UpdatedAt,
			&createdBy,
			&updatedBy,
			&bi.PartCode,
			&bi.AddressCode,
			&bi.Name,
			&bi.Price,
			&bi.Qty,
		)
		if err != nil {
			return nil, err
		}

		if paymentMethod.Valid {
			bi.PaymentMethod = paymentMethod.String
		}
		if paymentRef.Valid {
			bi.PaymentRef = paymentRef.String
		}
		if memberID.Valid {
			bi.MemberID = memberID.String
		}
		if createdBy.Valid {
			bi.CreatedBy = createdBy.String
		}
		if updatedBy.Valid {
			bi.UpdatedBy = updatedBy.String
		}

		results = append(results, bi)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return results, nil
}

func (r *reportRepositoryPG) GetAllParts(ctx context.Context) ([]PartMaster, error) {
	// Note: the raw "image" column stores a (potentially large) base64 blob.
	// Transferring it for every part made the parts report huge and slow, and a
	// blob is unusable in a CSV anyway — so we emit a lightweight presence flag
	// ('Y' / '') instead of the full image data. CSV structure is unchanged.
	rows, err := r.db.QueryContext(ctx, `
		SELECT
			"code", "bar_code", "category_id", "unit_id", "name", "name_th",
			COALESCE("receipt_name", ''), "details", "cost", "price",
			CASE WHEN "image" IS NULL OR "image" = '' THEN '' ELSE 'Y' END AS "image",
			"is_active"
		FROM "part_master"
		ORDER BY "code" ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var parts []PartMaster
	for rows.Next() {
		var p PartMaster
		var barCode, categoryID, unitID, nameTH, receiptName, details, image sql.NullString
		var cost sql.NullFloat64
		var isActive sql.NullBool

		err := rows.Scan(
			&p.Code,
			&barCode,
			&categoryID,
			&unitID,
			&p.Name,
			&nameTH,
			&receiptName,
			&details,
			&cost,
			&p.Price,
			&image,
			&isActive,
		)
		if err != nil {
			return nil, err
		}

		if barCode.Valid {
			p.BarCode = barCode.String
		}
		if categoryID.Valid {
			p.CategoryID = categoryID.String
		}
		if unitID.Valid {
			p.UnitID = unitID.String
		}
		if nameTH.Valid {
			p.NameTH = nameTH.String
		}
		if receiptName.Valid {
			p.ReceiptName = receiptName.String
		}
		if details.Valid {
			p.Details = details.String
		}
		if cost.Valid {
			p.Cost = cost.Float64
		}
		if image.Valid {
			p.Image = image.String
		}
		if isActive.Valid {
			p.IsActive = isActive.Bool
		}

		parts = append(parts, p)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return parts, nil
}

func (r *reportRepositoryPG) GetAllAddresses(ctx context.Context) ([]Address, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT 
			"code", "part_code", "store_id", "shelf", "qty", "min", "max", "rop", "remarks"
		FROM "address_master"
		ORDER BY "code" ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var addresses []Address
	for rows.Next() {
		var a Address
		var shelf, remarks sql.NullString
		var qty, min, max, rop sql.NullInt64

		err := rows.Scan(
			&a.Code,
			&a.PartCode,
			&a.StoreID,
			&shelf,
			&qty,
			&min,
			&max,
			&rop,
			&remarks,
		)
		if err != nil {
			return nil, err
		}

		if shelf.Valid {
			a.Shelf = shelf.String
		}
		if qty.Valid {
			a.Qty = int(qty.Int64)
		}
		if min.Valid {
			a.Min = int(min.Int64)
		}
		if max.Valid {
			a.Max = int(max.Int64)
		}
		if rop.Valid {
			a.Rop = int(rop.Int64)
		}
		if remarks.Valid {
			a.Remarks = remarks.String
		}

		addresses = append(addresses, a)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return addresses, nil
}
