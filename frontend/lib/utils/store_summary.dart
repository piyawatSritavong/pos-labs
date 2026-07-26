String formatPartStoreSummary(List<dynamic>? rawAddresses) {
  final grouped = <String, ({String label, num qty})>{};
  for (final raw in rawAddresses ?? const []) {
    if (raw is! Map) continue;
    final store = raw['store'];
    if (store is! Map) continue;
    final storeId = store['id']?.toString() ?? '';
    if (storeId.isEmpty) continue;
    final label = (store['labelTh'] ?? store['label'] ?? storeId)
        .toString()
        .trim();
    final rawQty = raw['qty'];
    final qty = rawQty is num
        ? rawQty
        : num.tryParse(rawQty?.toString() ?? '') ?? 0;
    final current = grouped[storeId];
    grouped[storeId] = (
      label: label.isEmpty ? storeId : label,
      qty: (current?.qty ?? 0) + qty,
    );
  }
  if (grouped.isEmpty) return '-';

  int storeRank(String id) {
    if (id == 'main') return 0;
    if (id == 'vehicle_POS001') return 1;
    if (id == 'store_00001') return 2;
    return 3;
  }

  final entries = grouped.entries.toList()
    ..sort((a, b) {
      final rank = storeRank(a.key).compareTo(storeRank(b.key));
      return rank != 0 ? rank : a.value.label.compareTo(b.value.label);
    });
  String qtyText(num qty) =>
      qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
  return entries
      .map((entry) => '${entry.value.label} (${qtyText(entry.value.qty)})')
      .join(', ');
}
