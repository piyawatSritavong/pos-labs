package handlers

import (
	"net/http"

	"backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type CompanyHandler struct {
	company repository.CompanyRepository
}

func NewCompanyHandler(company repository.CompanyRepository) *CompanyHandler {
	return &CompanyHandler{company: company}
}

func (h *CompanyHandler) Get(c *gin.Context) {
	company, err := h.company.Get(c.Request.Context())
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "company_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_company"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"taxId":              company.TaxID,
		"companyName":        company.CompanyName,
		"companyNameTh":      company.CompanyNameTH,
		"companyAddress":     company.CompanyAddress,
		"companyAddressTh":   company.CompanyAddressTH,
		"phone":              company.Phone,
		"email":              company.Email,
		"website":            company.Website,
		"logoUrl":            company.LogoURL,
		"taxRate":            company.TaxRate,
		"taxType":            company.TaxType,
		"receiptFooter":      company.ReceiptFooter,
		"businessHours":      company.BusinessHours,
		"memberDiscountRate": company.MemberDiscountRate,
		"roundToWholeBaht":   company.RoundToWholeBaht,
	})
}

func (h *CompanyHandler) Update(c *gin.Context) {
	var req struct {
		CompanyName      string  `json:"companyName" binding:"required"`
		CompanyNameTH    string  `json:"companyNameTh" binding:"required"`
		CompanyAddress   string  `json:"companyAddress" binding:"required"`
		CompanyAddressTH string  `json:"companyAddressTh" binding:"required"`
		Phone            string  `json:"phone" binding:"required"`
		Email            *string `json:"email"`
		Website          *string `json:"website"`
		LogoURL          *string `json:"logoUrl"`
		TaxRate          float64 `json:"taxRate" binding:"required"`
		TaxType          string  `json:"taxType" binding:"required"`
		// Optional — if omitted by the client, the existing value is preserved.
		ReceiptFooter      *string  `json:"receiptFooter"`
		BusinessHours      *string  `json:"businessHours"`
		MemberDiscountRate *float64 `json:"memberDiscountRate"`
		RoundToWholeBaht   *bool    `json:"roundToWholeBaht"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	// Get existing company to preserve tax_id (and receipt_footer if not in request)
	existing, err := h.company.Get(c.Request.Context())
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "company_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_company"})
		return
	}

	receiptFooter := existing.ReceiptFooter
	if req.ReceiptFooter != nil {
		receiptFooter = *req.ReceiptFooter
	}
	businessHours := existing.BusinessHours
	if req.BusinessHours != nil {
		businessHours = *req.BusinessHours
	}
	memberDiscountRate := existing.MemberDiscountRate
	if req.MemberDiscountRate != nil {
		memberDiscountRate = *req.MemberDiscountRate
		if memberDiscountRate < 0 || memberDiscountRate > 1 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":   "invalid_member_discount_rate",
				"message": "ส่วนลดสมาชิกต้องอยู่ระหว่าง 0 ถึง 1 (0 = ปิด, 0.05 = 5%)",
			})
			return
		}
	}
	roundToWholeBaht := existing.RoundToWholeBaht
	if req.RoundToWholeBaht != nil {
		roundToWholeBaht = *req.RoundToWholeBaht
	}

	company := &repository.Company{
		TaxID:              existing.TaxID,
		CompanyName:        req.CompanyName,
		CompanyNameTH:      req.CompanyNameTH,
		CompanyAddress:     req.CompanyAddress,
		CompanyAddressTH:   req.CompanyAddressTH,
		Phone:              req.Phone,
		Email:              req.Email,
		Website:            req.Website,
		LogoURL:            req.LogoURL,
		TaxRate:            req.TaxRate,
		TaxType:            req.TaxType,
		ReceiptFooter:      receiptFooter,
		BusinessHours:      businessHours,
		MemberDiscountRate: memberDiscountRate,
		RoundToWholeBaht:   roundToWholeBaht,
	}

	if err := h.company.Update(c.Request.Context(), company); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_company"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"taxId":              company.TaxID,
		"companyName":        company.CompanyName,
		"companyNameTh":      company.CompanyNameTH,
		"companyAddress":     company.CompanyAddress,
		"companyAddressTh":   company.CompanyAddressTH,
		"phone":              company.Phone,
		"email":              company.Email,
		"website":            company.Website,
		"logoUrl":            company.LogoURL,
		"taxRate":            company.TaxRate,
		"taxType":            company.TaxType,
		"receiptFooter":      company.ReceiptFooter,
		"businessHours":      company.BusinessHours,
		"memberDiscountRate": company.MemberDiscountRate,
		"roundToWholeBaht":   company.RoundToWholeBaht,
	})
}
