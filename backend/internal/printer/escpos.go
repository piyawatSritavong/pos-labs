// Package printer builds ESC-POS byte streams for receipt printing on 80mm
// thermal printers driven by a "Generic / Text Only" Windows driver.
//
// The driver passes whatever bytes we send straight through to the device,
// so we emit raw ESC-POS commands (init / alignment / size / cut) interleaved
// with either ASCII-safe text or Thai CP874 bytes. Most modern thermal printers
// (Epson-compatible) honor these commands.
package printer

import (
	"bytes"
	"encoding/hex"
	"fmt"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// 80mm Generic/Text Only Windows printers typically render at 32 chars per
// line for normal-size font and 16 chars per line for double-width.
const (
	LineCols      = 32
	LineColsLarge = 16
	ModeASCII     = "ascii"
	ModeThaiCP874 = "thai_cp874"

	DefaultDrawerKickCommandHex = "1B700019FA"
)

var CommonDrawerKickCommandHexes = []string{
	"1B700019FA",
	"1B700032FA",
	"1B700119FA",
	"1B700132FA",
}

// EscPos commands. See https://reference.epson-biz.com/modules/ref_escpos/
var (
	cmdInit     = []byte{0x1B, 0x40}       // ESC @ — reset printer
	cmdAlignL   = []byte{0x1B, 0x61, 0x00} // ESC a 0 — left
	cmdAlignC   = []byte{0x1B, 0x61, 0x01} // ESC a 1 — center
	cmdAlignR   = []byte{0x1B, 0x61, 0x02} // ESC a 2 — right
	cmdNormal   = []byte{0x1B, 0x21, 0x00} // ESC ! 0 — normal size
	cmdDouble   = []byte{0x1B, 0x21, 0x30} // ESC ! 0x30 — double height + double width
	cmdBold     = []byte{0x1B, 0x45, 0x01}
	cmdNoBold   = []byte{0x1B, 0x45, 0x00}
	cmdLF       = []byte{0x0A}
	cmdCutFull  = []byte{0x1D, 0x56, 0x00} // GS V 0 — full cut
	cmdFeedCut3 = []byte{0x1B, 0x64, 0x03} // ESC d 3 — feed 3 lines before manual tear
)

// Builder accumulates ESC-POS bytes. Methods are chainable.
type Builder struct {
	buf bytes.Buffer
}

func New() *Builder { return &Builder{} }

func (b *Builder) Init() *Builder   { b.buf.Write(cmdInit); return b }
func (b *Builder) Center() *Builder { b.buf.Write(cmdAlignC); return b }
func (b *Builder) Left() *Builder   { b.buf.Write(cmdAlignL); return b }
func (b *Builder) Right() *Builder  { b.buf.Write(cmdAlignR); return b }
func (b *Builder) Double() *Builder { b.buf.Write(cmdDouble); return b }
func (b *Builder) Normal() *Builder { b.buf.Write(cmdNormal); return b }
func (b *Builder) Bold() *Builder   { b.buf.Write(cmdBold); return b }
func (b *Builder) NoBold() *Builder { b.buf.Write(cmdNoBold); return b }

// CodeTable selects the printer's character code table. The exact mapping
// of `n` is firmware-specific but most Epson-compatible 80mm thermal printers
// honor:
//   - 0   = CP437 (USA / Standard Europe)
//   - 18  = CP874 / TIS-620 (Thai) on some Epson models
//   - 20  = CP874 (Thai)        on other firmwares
//   - 21  = CP874 (Thai code 18) on Star/Bixolon-style printers
//
// We default to 21 because it works on the Generic/Text Only path of most
// devices marketed in Thailand. Override via RECEIPT_CHARSET in .env.
func (b *Builder) CodeTable(n byte) *Builder {
	b.buf.Write([]byte{0x1B, 0x74, n})
	return b
}

// Text writes a string after transcoding it from UTF-8 to CP874 (Thai).
// ASCII bytes pass through unchanged. Use this for any line that may contain
// Thai characters; the BuildReceipt helper does this for you.
func (b *Builder) Text(s string) *Builder { b.buf.Write(EncodeCP874(s)); return b }

// Line writes the string (transcoded to CP874) followed by LF.
func (b *Builder) Line(s string) *Builder { b.buf.Write(EncodeCP874(s)); b.buf.Write(cmdLF); return b }

// LF prints n empty lines (default 1).
func (b *Builder) LF(n int) *Builder {
	if n <= 0 {
		n = 1
	}
	for i := 0; i < n; i++ {
		b.buf.Write(cmdLF)
	}
	return b
}

// Separator prints `width` dashes followed by LF (default LineCols).
func (b *Builder) Separator(width int) *Builder {
	if width <= 0 {
		width = LineCols
	}
	return b.Line(strings.Repeat("-", width))
}

// Cut feeds a few lines and issues a full cut command. If the printer has no
// cutter, the feed at least pushes the receipt past the tear bar.
func (b *Builder) Cut() *Builder {
	b.buf.Write(cmdFeedCut3)
	b.buf.Write(cmdCutFull)
	return b
}

// DrawerPulse writes an ESC/POS cash-drawer pulse. The exact command depends
// on whether the drawer is wired to DK1/DK2 and on printer firmware timing.
func (b *Builder) DrawerPulse(command []byte) *Builder {
	b.buf.Write(BuildDrawerKick(command))
	return b
}

// LeftRight emits a single line with `left` flush-left and `right` flush-right
// padded out to `width` columns. Truncates `left` if it would overflow.
func (b *Builder) LeftRight(left, right string, width int) *Builder {
	if width <= 0 {
		width = LineCols
	}
	rL := utf8.RuneCountInString(left)
	rR := utf8.RuneCountInString(right)
	if rL+rR+1 > width {
		// Truncate left so the line still fits with one space gap.
		max := width - rR - 1
		if max < 1 {
			max = 1
		}
		left = truncateRunes(left, max)
		rL = utf8.RuneCountInString(left)
	}
	pad := width - rL - rR
	if pad < 1 {
		pad = 1
	}
	// Transcode each segment to CP874 so Thai labels render correctly.
	b.buf.Write(EncodeCP874(left))
	b.buf.Write(EncodeCP874(strings.Repeat(" ", pad)))
	b.buf.Write(EncodeCP874(right))
	b.buf.Write(cmdLF)
	return b
}

// Bytes returns the accumulated ESC-POS payload.
func (b *Builder) Bytes() []byte { return b.buf.Bytes() }

// ─────────────────────────────────────────────────────────────────────────────
// High-level receipt template.

// ReceiptItem is one cart line on the receipt.
type ReceiptItem struct {
	Code      string
	Name      string
	Qty       int
	UnitPrice float64
	LineTotal float64
}

// ReceiptParams holds everything BuildReceipt needs to produce a final receipt.
// Strings can be empty — empty fields are omitted from the output rather than
// emitting blank lines.
type ReceiptParams struct {
	CompanyNameTh   string
	CompanyAddrTh   string
	BusinessHours   string // e.g. "เปิดทุกวัน 05.00-20.00น."
	TaxID           string
	Phone           string
	Website         string
	ReceiptFooter   string
	Title           string
	BillID          string
	POSID           string
	CustomerName    string
	CashierName     string
	PaymentMethod   string // e.g. "เงินสด", "โอน", "เงินเชื่อ"
	IssuedAt        time.Time
	Items           []ReceiptItem
	Subtotal        float64
	MemberDiscount  float64
	Discount        float64
	Rounding        float64
	AmountAfterDisc float64
	TaxRatePercent  int // e.g. 7
	Tax             float64
	Total           float64
	ReceivedAmount  float64
	ChangeAmount    float64
	HasReceived     bool
	HasChange       bool
	NumberOfCopies  int  // optional — 1 if zero
	CodeTable       byte // ESC t code page; 0 falls back to default Thai code page (21)
	PrintMode       string
	OpenDrawer      bool
	DrawerKick      []byte
}

// BuildReceipt assembles the ESC-POS bytes for one receipt copy. The caller
// passes the bytes to PrintRaw which writes them to the LPT port.
func BuildReceipt(p ReceiptParams) []byte {
	switch NormalizePrintMode(p.PrintMode) {
	case ModeThaiCP874:
		return buildReceiptThaiCP874(p)
	default:
		return buildReceiptASCII(p)
	}
}

func NormalizePrintMode(mode string) string {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case ModeThaiCP874, "thai", "cp874", "tis620", "tis-620":
		return ModeThaiCP874
	default:
		return ModeASCII
	}
}

func buildReceiptThaiCP874(p ReceiptParams) []byte {
	b := New().Init()

	// CRITICAL: switch the printer to a Thai code page before any text.
	// Without this the printer falls back to its default (often CP936 Chinese
	// or CP437 USA) and Thai bytes render as Chinese glyphs. Code page 21
	// works on most Generic/Text Only printers sold in Thailand; override via
	// RECEIPT_CHARSET in .env if the device requires a different value.
	ct := p.CodeTable
	if ct == 0 {
		ct = 21
	}
	b.CodeTable(ct)

	// Layout follows the slip the shop already gives customers: name and hours
	// at the top, labelled document fields, a four-column item table, then the
	// money read top to bottom — goods, what came off, what rounding did, what
	// is owed, and what changed hands.
	b.Center()
	if p.CompanyNameTh != "" {
		b.Double().Line(p.CompanyNameTh).Normal()
	}
	if hours := strings.TrimSpace(p.BusinessHours); hours != "" {
		if p.Phone != "" {
			b.Line(hours + " " + p.Phone)
		} else {
			b.Line(hours)
		}
	} else if p.Phone != "" {
		b.Line(fmt.Sprintf("โทร. %s", p.Phone))
	}
	title := strings.TrimSpace(p.Title)
	if title == "" {
		title = "ใบเสร็จรับเงิน/ใบกำกับภาษีอย่างย่อ"
	}
	b.Line(title)
	b.LF(1)

	// Document fields, label then value.
	b.Left()
	b.LeftRight("เลขที่ใบ", p.BillID, LineCols)
	if p.POSID != "" {
		b.LeftRight("เครื่อง:", p.POSID, LineCols)
	}
	b.LeftRight("วันที่:", formatThaiDateTime(p.IssuedAt), LineCols)
	if p.CashierName != "" {
		b.LeftRight("พนักงาน:", p.CashierName, LineCols)
	}
	customer := strings.TrimSpace(p.CustomerName)
	if customer == "" {
		customer = "General Customer"
	}
	b.LeftRight("ลูกค้า:", customer, LineCols)
	b.Separator(0)

	// Item table. The name gets its own line whenever the columns would not
	// leave room for it, which is most of the time in Thai.
	b.LeftRight("สินค้า", itemColumns("จำนวน", "ราคา", "รวม"), LineCols)
	b.Separator(0)
	for _, it := range p.Items {
		b.Line(truncateRunes(it.Name, LineCols))
		b.Right()
		b.Line(itemColumns(
			fmtQty(it.Qty),
			fmtMoney(it.UnitPrice),
			fmtMoney(it.LineTotal),
		))
		b.Left()
	}
	b.Separator(0)

	// Money.
	b.LeftRight("ราคารวม", fmtMoney(p.Subtotal), LineCols)
	b.LeftRight("ส่วนลดสมาชิก", fmtMoney(p.MemberDiscount), LineCols)
	b.LeftRight("ส่วนลด", fmtMoney(p.Discount), LineCols)
	if p.Rounding != 0 {
		b.LeftRight("ปัดเศษ", fmtMoney(p.Rounding), LineCols)
	}
	b.Separator(0)
	b.Bold().LeftRight("รวมยอดสุทธิ", fmtMoney(p.Total), LineCols).NoBold()

	if p.PaymentMethod != "" {
		b.LeftRight("ประเภทการชำระเงิน", p.PaymentMethod, LineCols)
	}
	// Cash lines only when cash actually changed hands; a card sale printing
	// "รับเงิน 0.00" reads like a mistake.
	if p.HasReceived {
		b.LeftRight("รับเงิน", fmtMoney(p.ReceivedAmount), LineCols)
	}
	if p.HasChange {
		b.LeftRight("ทอนเงิน", fmtMoney(p.ChangeAmount), LineCols)
	}

	// Footer — editable in Backoffice → Company → ข้อความท้ายใบเสร็จ.
	if strings.TrimSpace(p.ReceiptFooter) != "" {
		b.LF(1)
		b.Center()
		for _, ln := range strings.Split(p.ReceiptFooter, "\n") {
			b.Line(strings.TrimRight(ln, "\r"))
		}
		b.Left()
	}

	// Feed + cut. Even printers without a cutter benefit from a few extra
	// lines so the user can tear by hand.
	if p.OpenDrawer {
		b.DrawerPulse(p.DrawerKick)
	}
	b.LF(2).Cut()
	return b.Bytes()
}

func buildReceiptASCII(p ReceiptParams) []byte {
	b := New().Init().CodeTable(0)

	companyName := firstReceiptASCII(p.CompanyNameTh, "POS SALE")
	companyAddr := asciiText(p.CompanyAddrTh)
	footer := firstReceiptASCII(p.ReceiptFooter, "Thank you")

	b.Center()
	b.Double().Line(truncateRunes(companyName, LineColsLarge)).Normal()
	if companyAddr != "" {
		b.Line(truncateRunes(companyAddr, LineCols))
	}
	if taxID := asciiText(p.TaxID); taxID != "" {
		b.Line("TAX ID " + taxID)
	}
	if phone := asciiText(p.Phone); phone != "" {
		b.Line("TEL " + phone)
	}
	if website := asciiText(p.Website); website != "" {
		b.Line("WEB " + website)
	}
	b.LF(1)

	b.Bold().Line(firstReceiptASCII(p.Title, "RECEIPT")).NoBold()
	if billID := asciiText(p.BillID); billID != "" {
		b.Line("NO " + billID)
	}
	b.LF(1)

	b.Left()
	if cashier := asciiText(p.CashierName); cashier != "" {
		b.Line("Cashier: " + cashier)
	}
	b.Line("Date: " + time.Now().Format("2006-01-02 15:04"))
	b.Separator(0)

	for _, it := range p.Items {
		name := receiptItemNameASCII(it)
		b.Line(truncateRunes(name, LineCols))
		left := fmt.Sprintf("  %s  %d x %s", asciiText(it.Code), it.Qty, fmtMoney(it.UnitPrice))
		b.LeftRight(left, fmtMoney(it.LineTotal), LineCols)
	}
	b.Separator(0)

	b.LeftRight("Subtotal", fmtMoney(p.Subtotal), LineCols)
	b.LeftRight("Discount", "-"+fmtMoney(p.Discount), LineCols)
	b.LeftRight("After discount", fmtMoney(p.AmountAfterDisc), LineCols)
	b.LeftRight(fmt.Sprintf("VAT %d%%", p.TaxRatePercent), fmtMoney(p.Tax), LineCols)
	b.Separator(0)

	b.Double().Line("TOTAL").Normal()
	b.Double().Right().Line(fmtMoney(p.Total)).Normal()
	b.Left()

	if method := asciiText(p.PaymentMethod); method != "" {
		b.LeftRight("Payment", method, LineCols)
	}
	if p.HasReceived {
		b.LeftRight("Received", fmtMoney(p.ReceivedAmount), LineCols)
	} else {
		b.LeftRight("Received", "-", LineCols)
	}
	if p.HasChange {
		b.LeftRight("Change", fmtMoney(p.ChangeAmount), LineCols)
	} else {
		b.LeftRight("Change", "-", LineCols)
	}
	b.LF(1)
	b.Center().Line("VAT INCLUDED")

	if footer != "" {
		b.LF(1)
		for _, ln := range strings.Split(footer, "\n") {
			if clean := asciiText(ln); clean != "" {
				b.Line(truncateRunes(clean, LineCols))
			}
		}
	}

	if p.OpenDrawer {
		b.DrawerPulse(p.DrawerKick)
	}
	b.LF(2).Cut()
	return b.Bytes()
}

func ParseDrawerKickCommand(raw string) ([]byte, string, error) {
	clean := NormalizeHexCommand(raw)
	if clean == "" {
		clean = DefaultDrawerKickCommandHex
	}
	data, err := hex.DecodeString(clean)
	if err != nil {
		return nil, "", fmt.Errorf("invalid drawer kick command %q: %w", raw, err)
	}
	if len(data) == 0 {
		return nil, "", fmt.Errorf("invalid drawer kick command %q: command is empty", raw)
	}
	return data, clean, nil
}

func MustDrawerKickCommand(raw string) ([]byte, string) {
	data, normalized, err := ParseDrawerKickCommand(raw)
	if err == nil {
		return data, normalized
	}
	data, normalized, _ = ParseDrawerKickCommand(DefaultDrawerKickCommandHex)
	return data, normalized
}

func BuildDrawerKick(command []byte) []byte {
	if len(command) == 0 {
		command, _ = hex.DecodeString(DefaultDrawerKickCommandHex)
	}
	out := make([]byte, len(command))
	copy(out, command)
	return out
}

func HexCommand(command []byte) string {
	if len(command) == 0 {
		return DefaultDrawerKickCommandHex
	}
	return strings.ToUpper(hex.EncodeToString(command))
}

func NormalizeHexCommand(raw string) string {
	clean := strings.TrimSpace(raw)
	clean = strings.TrimPrefix(clean, "0x")
	clean = strings.TrimPrefix(clean, "0X")
	replacer := strings.NewReplacer(
		" ", "",
		"\t", "",
		"\n", "",
		"\r", "",
		"-", "",
		":", "",
		",", "",
		"0x", "",
		"0X", "",
		`\x`, "",
		`\X`, "",
	)
	return strings.ToUpper(replacer.Replace(clean))
}

func firstReceiptASCII(raw, fallback string) string {
	clean := asciiText(raw)
	if clean != "" {
		return clean
	}
	return fallback
}

func receiptItemNameASCII(it ReceiptItem) string {
	if containsNonASCII(it.Name) {
		code := asciiText(it.Code)
		if code == "" {
			return "ITEM"
		}
		return "ITEM " + code
	}
	if name := asciiText(it.Name); name != "" {
		return name
	}
	code := asciiText(it.Code)
	if code == "" {
		return "ITEM"
	}
	return "ITEM " + code
}

func containsNonASCII(s string) bool {
	for _, r := range s {
		if r > 0x7F {
			return true
		}
	}
	return false
}

func asciiText(s string) string {
	var out strings.Builder
	lastSpace := true
	for _, r := range s {
		switch {
		case r >= 0x20 && r <= 0x7E:
			out.WriteByte(byte(r))
			lastSpace = r == ' '
		case r == '\n' || r == '\r' || r == '\t':
			if !lastSpace {
				out.WriteByte(' ')
				lastSpace = true
			}
		default:
			if !lastSpace {
				out.WriteByte(' ')
				lastSpace = true
			}
		}
	}
	return strings.Join(strings.Fields(out.String()), " ")
}

// truncateRunes returns s shortened to at most max runes (not bytes).
func truncateRunes(s string, max int) string {
	if max <= 0 {
		return ""
	}
	if utf8.RuneCountInString(s) <= max {
		return s
	}
	out := make([]rune, 0, max)
	for _, r := range s {
		if len(out) >= max {
			break
		}
		out = append(out, r)
	}
	return string(out)
}

func fmtMoney(v float64) string {
	return fmt.Sprintf("%.2f", v)
}

// itemColumns right-aligns the three numeric columns of the item table into a
// fixed width so the figures line up down the slip.
func itemColumns(qty, price, total string) string {
	return fmt.Sprintf("%6s %8s %9s", qty, price, total)
}

// fmtQty prints whole quantities without a decimal tail; the reference slip
// only shows decimals for goods sold by weight.
func fmtQty(qty int) string {
	return strconv.Itoa(qty)
}

// formatThaiDateTime renders the Buddhist-era date the shop's customers read.
func formatThaiDateTime(at time.Time) string {
	if at.IsZero() {
		at = time.Now()
	}
	local := at.In(time.FixedZone("Asia/Bangkok", 7*60*60))
	return fmt.Sprintf("%02d/%02d/%d %02d:%02d",
		local.Day(), int(local.Month()), local.Year()+543, local.Hour(), local.Minute())
}
