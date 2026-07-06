/// App-wide feature toggles.
///
/// Credit / "เงินเซ็น" (credit-term) sales. When false, the POS payment picker
/// hides the option and every back-office / daily-close summary omits the
/// credit-term row. Enabled on this branch (client-ppsale/demo); the jaiheng
/// deploy branch sets this to false.
const bool kEnableCreditTerm = true;
