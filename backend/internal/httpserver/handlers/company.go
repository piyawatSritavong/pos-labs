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
		"taxId":          company.TaxID,
		"companyName":    company.CompanyName,
		"companyNameTh":  company.CompanyNameTH,
		"companyAddress": company.CompanyAddress,
		"companyAddressTh": company.CompanyAddressTH,
		"phone":          company.Phone,
		"email":          company.Email,
		"website":        company.Website,
		"logoUrl":        company.LogoURL,
		"taxRate":        company.TaxRate,
		"taxType":        company.TaxType,
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
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	// Get existing company to preserve tax_id
	existing, err := h.company.Get(c.Request.Context())
	if err != nil {
		if repository.IsNotFoundError(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "company_not_found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_get_company"})
		return
	}

	company := &repository.Company{
		TaxID:            existing.TaxID,
		CompanyName:      req.CompanyName,
		CompanyNameTH:    req.CompanyNameTH,
		CompanyAddress:   req.CompanyAddress,
		CompanyAddressTH: req.CompanyAddressTH,
		Phone:            req.Phone,
		Email:            req.Email,
		Website:          req.Website,
		LogoURL:          req.LogoURL,
		TaxRate:          req.TaxRate,
		TaxType:          req.TaxType,
	}

	if err := h.company.Update(c.Request.Context(), company); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed_to_update_company"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"taxId":          company.TaxID,
		"companyName":    company.CompanyName,
		"companyNameTh":  company.CompanyNameTH,
		"companyAddress": company.CompanyAddress,
		"companyAddressTh": company.CompanyAddressTH,
		"phone":          company.Phone,
		"email":          company.Email,
		"website":        company.Website,
		"logoUrl":        company.LogoURL,
		"taxRate":        company.TaxRate,
		"taxType":        company.TaxType,
	})
}

