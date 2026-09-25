import 'package:frontend/services/api_exception.dart';

/// Cloud checkout deliberately has no receipt printer. Treat only the two
/// configuration-level printer errors as a successful no-op; real print
/// failures still bubble up so a shop terminal can retry them.
Future<void> runReceiptPrintIfAvailable(
  Future<void> Function() printReceipt,
) async {
  try {
    await printReceipt();
  } catch (error) {
    if (!isReceiptPrinterUnavailable(error)) rethrow;
  }
}
