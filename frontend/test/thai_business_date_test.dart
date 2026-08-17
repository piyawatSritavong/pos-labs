import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/thai_business_date.dart';

void main() {
  test('the business day is Thailand time, not the device timezone', () {
    // 23:30 UTC is already the next day in Bangkok, and a bill opened then is
    // numbered with that later date.
    expect(thaiBusinessDateKey(DateTime.utc(2026, 8, 14, 23, 30)), '20260815');
    expect(thaiBusinessDateKey(DateTime.utc(2026, 8, 14, 16, 59)), '20260814');
    expect(thaiBusinessDateKey(DateTime.utc(2026, 8, 14, 17, 1)), '20260815');
  });

  test('single-digit months and days are padded like the ids are', () {
    expect(thaiBusinessDateKey(DateTime.utc(2026, 1, 2, 0, 0)), '20260102');
  });

  test('a bill id belongs to the day its number starts with', () {
    expect(isFromBusinessDay('20260814000001', '20260814'), isTrue);
    expect(isFromBusinessDay('20260814000001', '20260815'), isFalse);
    // Yesterday's leftover must not be mistaken for today's sale.
    expect(isFromBusinessDay('20260813000099', '20260814'), isFalse);
  });

  test('prefixed document ids are matched on their date part', () {
    expect(isFromBusinessDay('CN20260814000001', '20260814'), isTrue);
    expect(isFromBusinessDay('TR20260814000001', '20260815'), isFalse);
  });
}
