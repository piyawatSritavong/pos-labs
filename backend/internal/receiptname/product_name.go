package receiptname

import (
	"regexp"
	"strings"
	"unicode"
)

// Product holds the fields needed to select a printer-safe item name.
type Product struct {
	ID          string
	Code        string
	SKU         string
	ReceiptName string
	Name        string
	NameTH      string
	Size        string
	Grade       string
}

// SafeProductName returns an uppercase ASCII item name suitable for raw
// Generic/Text-only receipt printing.
func SafeProductName(p Product) string {
	name, _ := SafeProductNameWithSource(p)
	return name
}

// SafeProductNameWithSource returns the selected receipt name and its source.
func SafeProductNameWithSource(p Product) (string, string) {
	if name := cleanCandidate(p.ReceiptName, true); name != "" {
		return name, "receipt_name"
	}
	if name := cleanCandidate(buildCodeSizeGrade(p), false); name != "" {
		return name, "code_traits"
	}
	if name := cleanCandidate(buildTranslatedName(p), false); name != "" {
		return name, "translated_name"
	}
	if name := cleanCandidate(firstNonEmpty(p.Name, p.NameTH), false); name != "" {
		return name, "ascii_name"
	}
	if code := safeCode(firstNonEmpty(p.Code, p.SKU)); code != "" {
		return "ITEM " + code, "item_code"
	}
	if id := safeCode(p.ID); id != "" {
		return "PRODUCT " + id, "product_id"
	}
	return "ITEM", "fallback"
}

func buildCodeSizeGrade(p Product) string {
	code := safeCode(firstNonEmpty(p.Code, p.SKU))
	traits := productTraits(p)
	if code == "" || len(traits) == 0 {
		return ""
	}
	return strings.Join(append([]string{code}, traits...), " ")
}

func buildTranslatedName(p Product) string {
	raw := firstNonEmpty(p.NameTH, p.Name)
	upperRaw := strings.ToUpper(raw)
	base := ""
	switch {
	case strings.Contains(upperRaw, "MDF"):
		base = "MDF"
	case strings.Contains(upperRaw, "HMR"):
		base = "HMR"
	case strings.Contains(upperRaw, "OSB"):
		base = "OSB"
	case strings.Contains(raw, "เมลามีน"):
		base = "MELAMINE"
	case strings.Contains(raw, "ปาติเกิล"):
		base = "PARTICLE BOARD"
	case strings.Contains(raw, "ไม้อัดยาง") || strings.Contains(raw, "ไม้อัด"):
		base = "PLYWOOD"
	case strings.Contains(raw, "ลามิเนต"):
		base = "LAMINATE"
	case strings.Contains(raw, "ไม้คิ้ว"):
		base = "TRIM"
	case strings.Contains(raw, "ไม้โครง"):
		base = "FRAME WOOD"
	}
	if base == "" {
		return ""
	}
	parts := []string{base}
	traits := productTraits(p)
	if base == "MELAMINE" {
		traits = reorderMelamineTraits(traits)
	}
	parts = append(parts, traits...)
	return strings.Join(parts, " ")
}

func productTraits(p Product) []string {
	raw := strings.Join([]string{p.NameTH, p.Name, p.Size, p.Grade}, " ")
	traits := make([]string, 0, 6)

	if p.Size != "" {
		if size := cleanCandidate(p.Size, false); size != "" {
			traits = append(traits, size)
		}
	}
	for _, m := range regexp.MustCompile(`([0-9]+(?:\.[0-9]+)?)\s*มิล`).FindAllStringSubmatch(raw, -1) {
		traits = appendUnique(traits, m[1]+"MM")
	}
	for _, m := range regexp.MustCompile(`([0-9]+(?:\.[0-9]+)?)\s*นิ้ว`).FindAllStringSubmatch(raw, -1) {
		traits = appendUnique(traits, m[1]+"IN")
	}
	for _, m := range regexp.MustCompile(`[0-9]+(?:\s*[*]\s*[0-9]+(?:/[0-9]+)?)+`).FindAllString(raw, -1) {
		traits = appendUnique(traits, strings.ToUpper(strings.ReplaceAll(m, " ", "")))
	}
	for _, m := range regexp.MustCompile(`[0-9]+(?:-[0-9]+)?/[0-9]+(?:\s*[xX]\s*[0-9]+(?:-[0-9]+)?/[0-9]+)*`).FindAllString(raw, -1) {
		traits = appendUnique(traits, strings.ToUpper(strings.ReplaceAll(m, " ", "")))
	}
	if m := regexp.MustCompile(`เกรด\s*([A-Za-z0-9]+)`).FindStringSubmatch(raw); len(m) == 2 {
		traits = appendUnique(traits, strings.ToUpper(m[1]))
	}
	if p.Grade != "" {
		if grade := cleanCandidate(p.Grade, false); grade != "" {
			traits = appendUnique(traits, grade)
		}
	}

	replacements := []struct {
		th string
		en string
	}{
		{"ตราภูเขา", "PHUKHAO"},
		{"ขาว", "WHITE"},
		{"ดำ", "BLACK"},
		{"แดง", "RED"},
		{"น้ำเงิน", "BLUE"},
		{"ลาย", "PATTERN"},
		{"ขายส่ง", "WHOLESALE"},
		{"ไม้แบบ", "FORMWORK"},
	}
	for _, repl := range replacements {
		if strings.Contains(raw, repl.th) {
			traits = appendUnique(traits, repl.en)
		}
	}
	if regexp.MustCompile(`1\s*หน้า`).MatchString(raw) {
		traits = appendUnique(traits, "1S")
	}
	if regexp.MustCompile(`2\s*หน้า`).MatchString(raw) {
		traits = appendUnique(traits, "2S")
	}

	return traits
}

func cleanCandidate(raw string, allowShortCodeLike bool) string {
	clean := asciiClean(raw)
	if clean == "" {
		return ""
	}
	letters, digits := 0, 0
	for _, r := range clean {
		switch {
		case r >= 'A' && r <= 'Z':
			letters++
		case r >= '0' && r <= '9':
			digits++
		}
	}
	if letters == 0 {
		return ""
	}
	if len(strings.ReplaceAll(clean, " ", "")) < 3 {
		return ""
	}
	if letters < 2 && digits > 0 {
		return ""
	}
	if allowShortCodeLike {
		return clean
	}
	return clean
}

func asciiClean(raw string) string {
	var b strings.Builder
	lastSpace := true
	for _, r := range raw {
		switch {
		case r >= 'a' && r <= 'z':
			b.WriteRune(unicode.ToUpper(r))
			lastSpace = false
		case r >= 'A' && r <= 'Z':
			b.WriteRune(r)
			lastSpace = false
		case r >= '0' && r <= '9':
			b.WriteRune(r)
			lastSpace = false
		case r == '-' || r == '/' || r == '.' || r == '(' || r == ')' || r == '_':
			b.WriteRune(r)
			lastSpace = false
		case unicode.IsSpace(r):
			if !lastSpace {
				b.WriteByte(' ')
				lastSpace = true
			}
		default:
			if !lastSpace {
				b.WriteByte(' ')
				lastSpace = true
			}
		}
	}
	return strings.Join(strings.Fields(b.String()), " ")
}

func safeCode(raw string) string {
	return asciiClean(raw)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func appendUnique(items []string, value string) []string {
	value = strings.TrimSpace(value)
	if value == "" {
		return items
	}
	for _, item := range items {
		if item == value {
			return items
		}
	}
	return append(items, value)
}

func reorderMelamineTraits(traits []string) []string {
	color := make([]string, 0, len(traits))
	side := make([]string, 0, len(traits))
	size := make([]string, 0, len(traits))
	other := make([]string, 0, len(traits))
	for _, trait := range traits {
		switch {
		case trait == "WHITE" || trait == "BLACK" || trait == "RED" || trait == "BLUE" || trait == "PATTERN":
			color = append(color, trait)
		case strings.HasSuffix(trait, "S") && len(trait) <= 3:
			side = append(side, trait)
		case strings.HasSuffix(trait, "MM") || strings.HasSuffix(trait, "IN"):
			size = append(size, trait)
		default:
			other = append(other, trait)
		}
	}
	out := make([]string, 0, len(traits))
	out = append(out, color...)
	out = append(out, side...)
	out = append(out, size...)
	out = append(out, other...)
	return out
}
