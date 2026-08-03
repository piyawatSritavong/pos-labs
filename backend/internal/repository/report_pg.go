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
			COALESCE("receipt_name", ''), "details", "cost", "price", "min_price",
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
			&p.MinPrice,
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
			a."code", a."part_code", a."store_id", COALESCE(s."branch_id", ''),
			a."shelf", a."qty", a."min", a."max", a."rop", a."remarks",
			COALESCE(p."cost", 0), COALESCE(p."price", 0), COALESCE(p."min_price", 0)
		FROM "address_master" a
		LEFT JOIN "part_master" p ON p."code" = a."part_code"
		LEFT JOIN "store_master" s ON s."id" = a."store_id"
		WHERE a."is_active" = true
		  AND p."is_active" = true
		  AND s."location_type" = 'warehouse'
		ORDER BY a."code" ASC
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
			&a.BranchID,
			&shelf,
			&qty,
			&min,
			&max,
			&rop,
			&remarks,
			&a.Cost,
			&a.Price,
			&a.MinPrice,
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

func (r *reportRepositoryPG) GetIncomeReport(ctx context.Context, dateStart, dateEnd time.Time) (*IncomeReport, error) {
	rows, err := r.db.QueryContext(ctx, `
		WITH
		sales AS (
			SELECT "created_by" AS user_id, COALESCE(SUM("total_amount"), 0) AS revenue
			FROM "bill_master"
			WHERE "status" = 'completed' AND "created_at" >= $1 AND "created_at" < $2
			GROUP BY "created_by"
		),
		returns AS (
			SELECT "created_by" AS user_id, COALESCE(SUM("refund_amount"), 0) AS returns
			FROM "return_note_master"
			WHERE "status" <> 'cancelled' AND "created_at" >= $1 AND "created_at" < $2
			GROUP BY "created_by"
		),
		sold_costs AS (
			SELECT b."created_by" AS user_id, COALESCE(SUM(COALESCE(d."cost", 0) * d."qty"), 0) AS sold_cost
			FROM "bill_master" b
			JOIN "bill_item_detail" d ON d."bill_id" = b."id"
			WHERE b."status" = 'completed' AND b."created_at" >= $1 AND b."created_at" < $2
			GROUP BY b."created_by"
		),
		returned_costs AS (
			SELECT rn."created_by" AS user_id, COALESCE(SUM(COALESCE(bd."cost", 0) * ri."qty"), 0) AS returned_cost
			FROM "return_note_master" rn
			JOIN "return_note_item_detail" ri ON ri."return_note_id" = rn."id"
			JOIN "bill_item_detail" bd
			  ON bd."bill_id" = ri."reference_bill_id"
			 AND bd."part_code" = ri."part_code"
			 AND bd."address_code" = ri."address_code"
			WHERE rn."status" <> 'cancelled' AND rn."created_at" >= $1 AND rn."created_at" < $2
			GROUP BY rn."created_by"
		),
		expenses AS (
			SELECT "closed_by" AS user_id,
			       COALESCE(SUM(
			         COALESCE("fuel_amount", 0) + COALESCE("food_amount", 0) +
			         COALESCE("special_amount", 0) + COALESCE("tail_discount_amount", 0)
			       ), 0) AS expenses
			FROM "daily_close"
			WHERE "created_at" >= $1 AND "created_at" < $2
			GROUP BY "closed_by"
		)
		SELECT u."id", u."username", u."name",
		       COALESCE(s.revenue, 0), COALESCE(rt.returns, 0),
		       COALESCE(sc.sold_cost, 0), COALESCE(rc.returned_cost, 0),
		       COALESCE(e.expenses, 0)
		FROM "user" u
		LEFT JOIN sales s ON s.user_id = u."id"
		LEFT JOIN returns rt ON rt.user_id = u."id"
		LEFT JOIN sold_costs sc ON sc.user_id = u."id"
		LEFT JOIN returned_costs rc ON rc.user_id = u."id"
		LEFT JOIN expenses e ON e.user_id = u."id"
		WHERE u."is_active" = true
		   OR s.user_id IS NOT NULL
		   OR rt.user_id IS NOT NULL
		   OR sc.user_id IS NOT NULL
		   OR rc.user_id IS NOT NULL
		   OR e.user_id IS NOT NULL
		ORDER BY u."username"
	`, dateStart, dateEnd)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	report := &IncomeReport{}
	for rows.Next() {
		var account IncomeAccount
		if err := rows.Scan(
			&account.UserID,
			&account.Username,
			&account.Name,
			&account.Revenue,
			&account.Returns,
			&account.SoldCost,
			&account.ReturnedCost,
			&account.Expenses,
		); err != nil {
			return nil, err
		}
		account.NetRevenue = account.Revenue - account.Returns
		account.NetCost = account.SoldCost - account.ReturnedCost
		account.GrossProfit = account.NetRevenue - account.NetCost
		account.NetProfit = account.GrossProfit - account.Expenses
		report.Accounts = append(report.Accounts, account)

		report.Summary.Revenue += account.Revenue
		report.Summary.Returns += account.Returns
		report.Summary.SoldCost += account.SoldCost
		report.Summary.ReturnedCost += account.ReturnedCost
		report.Summary.Expenses += account.Expenses
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	report.Summary.NetRevenue = report.Summary.Revenue - report.Summary.Returns
	report.Summary.NetCost = report.Summary.SoldCost - report.Summary.ReturnedCost
	report.Summary.GrossProfit = report.Summary.NetRevenue - report.Summary.NetCost
	report.Summary.NetProfit = report.Summary.GrossProfit - report.Summary.Expenses

	expenseRows, err := r.db.QueryContext(ctx, `
		SELECT dc."id", dc."close_date", dc."created_at", dc."closed_by",
		       COALESCE(u."username", ''), COALESCE(u."name", ''),
		       dc."branch_id", dc."pos_id",
		       COALESCE(dc."fuel_amount", 0), COALESCE(dc."food_amount", 0),
		       COALESCE(dc."transfer_amount", 0), COALESCE(dc."special_amount", 0),
		       COALESCE(dc."tail_discount_amount", 0), COALESCE(dc."final_summary_amount", 0),
		       COALESCE(dc."notes", ''), COALESCE(dc."special_note", '')
		FROM "daily_close" dc
		LEFT JOIN "user" u ON u."id" = dc."closed_by"
		WHERE dc."created_at" >= $1 AND dc."created_at" < $2
		ORDER BY dc."created_at" DESC
	`, dateStart, dateEnd)
	if err != nil {
		return nil, err
	}
	defer expenseRows.Close()

	for expenseRows.Next() {
		var detail IncomeExpenseDetail
		if err := expenseRows.Scan(
			&detail.ID,
			&detail.CloseDate,
			&detail.CreatedAt,
			&detail.UserID,
			&detail.Username,
			&detail.Name,
			&detail.BranchID,
			&detail.POSID,
			&detail.FuelAmount,
			&detail.FoodAmount,
			&detail.TransferAmount,
			&detail.SpecialAmount,
			&detail.TailDiscountAmount,
			&detail.FinalSummaryAmount,
			&detail.Notes,
			&detail.SpecialNote,
		); err != nil {
			return nil, err
		}
		detail.TotalExpense = detail.FuelAmount + detail.FoodAmount + detail.SpecialAmount + detail.TailDiscountAmount
		report.ExpenseDetails = append(report.ExpenseDetails, detail)
	}
	if err := expenseRows.Err(); err != nil {
		return nil, err
	}

	return report, nil
}
