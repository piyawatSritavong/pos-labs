/// Reading a sold line back out of an API payload.
///
/// Bills come back from several endpoints whose item shapes differ — some carry
/// a unit price, some only a line total, and the key names vary. Every screen
/// that lists what was sold needs the same three numbers, so the unpacking
/// lives here instead of being re-derived (and quietly disagreeing) in each.
library;

double billLineQty(Map<String, dynamic> line) {
  final raw = line['qty'] ?? line['quantity'] ?? line['amountQty'];
  final qty = _toDouble(raw);
  return qty <= 0 ? 1 : qty;
}

/// Price of one piece. Falls back to dividing the line total when the payload
/// only carries the total, which is how the older list endpoints answer.
double billLineUnitPrice(Map<String, dynamic> line) {
  final direct = _toDouble(
    line['unitPrice'] ?? line['price'] ?? line['unit_price'],
  );
  if (direct > 0) return direct;
  final qty = billLineQty(line);
  return qty > 0 ? billLineTotal(line) / qty : 0;
}

double billLineTotal(Map<String, dynamic> line) {
  final direct = line['lineTotal'] ?? line['amount'] ?? line['total'];
  if (direct is num) return direct.toDouble();
  final parsed = double.tryParse(direct?.toString() ?? '');
  if (parsed != null) return parsed;
  return _toDouble(line['price'] ?? line['unitPrice']) * billLineQty(line);
}

/// "10 × ฿80.00" — the multiplication a customer checks the total against.
/// Whole counts lose the decimal tail; only goods sold by weight keep one.
String billLineQtyPriceLabel(Map<String, dynamic> line) {
  final qty = billLineQty(line);
  final qtyText = qty == qty.roundToDouble()
      ? qty.toStringAsFixed(0)
      : qty.toStringAsFixed(3);
  return '$qtyText × ฿${billLineUnitPrice(line).toStringAsFixed(2)}';
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
