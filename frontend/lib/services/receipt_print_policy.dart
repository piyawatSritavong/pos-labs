import 'package:frontend/services/api_exception.dart';

enum ReceiptPrintOutcome { printed, unavailable }

/// Cloud checkout deliberately has no receipt printer. Treat only the two
/// configuration-level printer errors as a successful no-op; real print
/// failures still bubble up so a shop terminal can retry them.
Future<ReceiptPrintOutcome> runReceiptPrintIfAvailable(
  Future<void> Function() printReceipt,
) async {
  try {
    await printReceipt();
    return ReceiptPrintOutcome.printed;
  } catch (error) {
    if (!isReceiptPrinterUnavailable(error)) rethrow;
    return ReceiptPrintOutcome.unavailable;
  }
}
