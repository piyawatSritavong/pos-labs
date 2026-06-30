/// App-wide feature toggles.
///
/// Credit / "เงินเซ็น" (credit-term) sales are disabled for this branch. When
/// false, the POS payment picker hides the option and every back-office /
/// daily-close summary omits the credit-term row. Flip to true to re-enable
/// the credit-term feature across the whole app.
const bool kEnableCreditTerm = false;
