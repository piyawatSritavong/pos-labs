String posErrorMessage(Object error) {
  final raw = error.toString();
  // The server says how many are actually on the vehicle; that number is the
  // answer the cashier needs, so pass it through rather than a generic line.
  if (raw.contains('not_enough_inventory')) {
    final available = RegExp(r'"availableQty":\s*(\d+)').firstMatch(raw);
    final requested = RegExp(r'"requestedQty":\s*(\d+)').firstMatch(raw);
    if (available != null && requested != null) {
      return 'สต๊อกไม่พอ ขอ ${requested.group(1)} ชิ้น '
          'เหลือในคลังของ POS นี้ ${available.group(1)} ชิ้น';
    }
    return 'สต๊อกในคลังประจำ POS ไม่พอ';
  }
  if (raw.contains('no_vehicle_stock') ||
      raw.contains('part_not_found') ||
      raw.contains('invalid_address_code')) {
    return 'สินค้านี้ไม่มีสต๊อกในคลังประจำ POS';
  }
  if (raw.contains('pos_store_not_configured')) {
    return 'POS นี้ยังไม่ได้ตั้งค่าคลังประจำเครื่อง';
  }
  // The bill moved on somewhere else — another tab paid it, cancelled it, or
  // an older build cancelled it on launch. The raw text says
  // "bill status must be 'new'", which tells a cashier nothing.
  if (raw.contains('invalid_bill_status')) {
    if (raw.contains("'cancelled'")) {
      return 'บิลนี้ถูกยกเลิกไปแล้ว (อาจถูกยกเลิกจากหน้าจอหรือแท็บอื่น) '
          'กรุณากดขึ้นบิลใหม่แล้วสแกนสินค้าอีกครั้ง';
    }
    if (raw.contains("'completed'")) {
      return 'บิลนี้ถูกชำระเงินไปแล้ว (อาจชำระจากหน้าจอหรือแท็บอื่น) '
          'กรุณาตรวจในประวัติการขายก่อนเก็บเงินซ้ำ';
    }
    return 'บิลนี้ไม่อยู่ในสถานะที่ชำระเงินได้แล้ว กรุณาขึ้นบิลใหม่';
  }
  return raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
}
