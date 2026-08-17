package handlers

// Line pricing is not fenced in.
//
// The shop asked for it: a van sells to walk-ins, regulars and other traders on
// the same round, and haggling both directions is the job. A floor computed
// from the catalog turned "sell it for what it's worth" into an error the
// cashier could not clear, and the price silently snapped back to what the
// catalog said — which reads as the system being broken, not as a rule.
//
// What remains enforced lives elsewhere and is about arithmetic, not policy:
// a line total must be a positive number (bills.go), and stock still has to
// exist before it can be sold.
//
// part_master keeps its min_price CHECK, so the catalog still records what the
// shop considers the floor. It is a reference for whoever sets prices, not a
// gate on the till.
