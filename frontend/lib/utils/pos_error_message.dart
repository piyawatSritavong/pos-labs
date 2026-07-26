String posErrorMessage(Object error) {
  final raw = error.toString();
  if (raw.contains('not_enough_inventory') ||
      raw.contains('no_vehicle_stock') ||
      raw.contains('part_not_found') ||
      raw.contains('invalid_address_code')) {
    return 'สินค้านี้ไม่มีสต๊อกในคลังประจำ POS';
  }
  if (raw.contains('pos_store_not_configured')) {
    return 'POS นี้ยังไม่ได้ตั้งค่าคลังประจำเครื่อง';
  }
  return raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
}
