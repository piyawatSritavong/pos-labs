package printer

// EncodeCP874 converts a UTF-8 Go string to Thai CP874 (Windows-874) bytes.
//
// Why: Generic / Text Only Windows printer drivers pass bytes through 1:1.
// Most 80mm thermal printers DO NOT understand UTF-8 — by default they decode
// incoming bytes as CP437 or CP936 (Simplified Chinese GBK), which is why
// untranscoded UTF-8 Thai bytes come out as Chinese glyphs.
//
// CP874 is the standard Thai code page (a.k.a. Windows-874 / TIS-620). Most
// thermal printers sold in Thailand support it via the ESC t command (see
// Builder.CodeTable).
//
// Mapping:
//   - U+0020..U+007E (printable ASCII)       → 0x20..0x7E (identical)
//   - U+00A0..U+00A0 (no-break space)         → 0xA0
//   - U+0E01..U+0E3A, U+0E3F..U+0E5B (Thai)   → 0xA1..0xFB
//   - Everything else                          → '?'
//
// The Thai Unicode block maps to CP874 by adding 0xA0 to the low byte
// (U+0E01 → 0xA1, U+0E02 → 0xA2, …, U+0E5B → 0xFB). U+0E3B..U+0E3E are
// reserved (unused), so we skip them.
func EncodeCP874(s string) []byte {
	out := make([]byte, 0, len(s))
	for _, r := range s {
		switch {
		case r >= 0x20 && r <= 0x7E:
			out = append(out, byte(r))
		case r == '\n':
			out = append(out, 0x0A)
		case r == '\r':
			out = append(out, 0x0D)
		case r == '\t':
			out = append(out, 0x09)
		case r == 0xA0:
			out = append(out, 0xA0)
		case r >= 0x0E01 && r <= 0x0E3A:
			out = append(out, byte(r-0x0E01)+0xA1)
		case r >= 0x0E3F && r <= 0x0E5B:
			out = append(out, byte(r-0x0E01)+0xA1)
		default:
			// Unknown / unmappable rune → ASCII '?'
			out = append(out, '?')
		}
	}
	return out
}
