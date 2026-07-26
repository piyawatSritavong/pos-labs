package handlers

func validateLinePrice(lineTotal float64, qty int, minUnitPrice, maxUnitPrice float64) (float64, float64, string) {
	minimum := minUnitPrice * float64(qty)
	maximum := maxUnitPrice * float64(qty)
	if lineTotal+0.0001 < minimum {
		return minimum, maximum, "price_below_minimum"
	}
	if lineTotal > maximum+0.0001 {
		return minimum, maximum, "price_above_catalog"
	}
	return minimum, maximum, ""
}
