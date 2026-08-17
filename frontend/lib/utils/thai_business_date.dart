/// The business day the POS numbers its documents by.
///
/// Bill ids are `YYYYMMDD` + a counter, and that date is Thailand time, not the
/// device's. Comparing the prefix is how "the sale in progress" is told apart
/// from "a bill left open overnight" without trusting a client clock's timezone.
String thaiBusinessDateKey(DateTime now) {
  final thai = now.toUtc().add(const Duration(hours: 7));
  return '${thai.year.toString().padLeft(4, '0')}'
      '${thai.month.toString().padLeft(2, '0')}'
      '${thai.day.toString().padLeft(2, '0')}';
}

/// Whether a document id was issued on the given business day.
bool isFromBusinessDay(String documentId, String dateKey) {
  // Return notes and transfers carry a prefix before the date; bills do not.
  final digits = documentId.replaceAll(RegExp(r'^[A-Za-z]+'), '');
  return digits.startsWith(dateKey);
}
