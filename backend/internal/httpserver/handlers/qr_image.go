package handlers

import (
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
)

const (
	maxFileSize = 5 * 1024 * 1024 // 5MB
	qrImageName = "qr-code"
)

type QRImageHandler struct {
	staticDir string
	imageDir  string
}

func NewQRImageHandler(staticDir string) *QRImageHandler {
	imageDir := filepath.Join(staticDir, "images")
	return &QRImageHandler{
		staticDir: staticDir,
		imageDir:  imageDir,
	}
}

func (h *QRImageHandler) Get(c *gin.Context) {
	// Try PNG first, then JPG
	pngPath := filepath.Join(h.imageDir, qrImageName+".png")
	jpgPath := filepath.Join(h.imageDir, qrImageName+".jpg")

	var imagePath string
	var contentType string

	if _, err := os.Stat(pngPath); err == nil {
		imagePath = pngPath
		contentType = "image/png"
	} else if _, err := os.Stat(jpgPath); err == nil {
		imagePath = jpgPath
		contentType = "image/jpeg"
	} else {
		c.JSON(http.StatusNotFound, gin.H{"error": "qr_image_not_found"})
		return
	}

	// Set headers for image display
	c.Header("Content-Type", contentType)
	c.Header("Content-Disposition", "inline")
	c.File(imagePath)
}

func (h *QRImageHandler) Put(c *gin.Context) {
	// Get content type from header
	contentType := c.GetHeader("Content-Type")
	if contentType == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "missing_content_type",
			"message": "Content-Type header is required (image/png or image/jpeg)",
		})
		return
	}

	// Validate content type
	var ext string
	var validType bool
	contentTypeLower := strings.ToLower(contentType)
	
	if strings.Contains(contentTypeLower, "image/png") {
		ext = ".png"
		validType = true
	} else if strings.Contains(contentTypeLower, "image/jpeg") || strings.Contains(contentTypeLower, "image/jpg") {
		ext = ".jpg"
		validType = true
	}

	if !validType {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_content_type",
			"message": "Content-Type must be image/png or image/jpeg",
		})
		return
	}

	// Limit request body size
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxFileSize)

	// Read image data
	imageData, err := io.ReadAll(c.Request.Body)
	if err != nil {
		if err.Error() == "http: request body too large" {
			c.JSON(http.StatusRequestEntityTooLarge, gin.H{
				"error":   "file_too_large",
				"message": "Image file size exceeds maximum allowed size (5MB)",
			})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "failed_to_read_image",
			"message": err.Error(),
		})
		return
	}

	// Validate magic bytes
	if len(imageData) < 4 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_image_data",
			"message": "Image data is too small or invalid",
		})
		return
	}

	// Check PNG magic bytes: 89 50 4E 47
	if ext == ".png" && (imageData[0] != 0x89 || imageData[1] != 0x50 || imageData[2] != 0x4E || imageData[3] != 0x47) {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_png_format",
			"message": "File does not appear to be a valid PNG image",
		})
		return
	}

	// Check JPEG magic bytes: FF D8 FF
	if ext == ".jpg" && (imageData[0] != 0xFF || imageData[1] != 0xD8 || imageData[2] != 0xFF) {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid_jpeg_format",
			"message": "File does not appear to be a valid JPEG image",
		})
		return
	}

	// Ensure directory exists
	if err := os.MkdirAll(h.imageDir, 0755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed_to_create_directory",
			"message": err.Error(),
		})
		return
	}

	// Delete existing QR code images (both .png and .jpg)
	pngPath := filepath.Join(h.imageDir, qrImageName+".png")
	jpgPath := filepath.Join(h.imageDir, qrImageName+".jpg")
	_ = os.Remove(pngPath) // Ignore error if file doesn't exist
	_ = os.Remove(jpgPath) // Ignore error if file doesn't exist

	// Save new image
	newImagePath := filepath.Join(h.imageDir, qrImageName+ext)
	if err := os.WriteFile(newImagePath, imageData, 0600); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed_to_save_image",
			"message": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "qr_image_updated",
		"path":    newImagePath,
	})
}

