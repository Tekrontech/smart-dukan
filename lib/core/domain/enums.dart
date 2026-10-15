/// Shared domain enums. Stored in the database by their `name`
/// (Drift `textEnum`), so never rename a value without a migration.
library;

enum BusinessType { mobileShop, kiryana, garments, pharmacy, wholesale, other }

/// Spec Section 9 roles.
enum UserRole { owner, manager, cashier, technician }

enum PartyType { customer, supplier, both }

/// How money moved. Cash → CASH, bank → BANK, JazzCash/Easypaisa → WALLET.
enum PaymentMethod { cash, bank, jazzcash, easypaisa }

/// How a sale was settled at the counter (spec 5.3).
///
/// - cash / wallet: fully paid now (wallet = bank or mobile wallet).
/// - udhaar: nothing paid now, all due.
/// - mixed: part paid now, rest udhaar (DECISIONS.md D-011).
/// - qist: instalment plan (Mobile Shop Pro).
enum SalePaymentMode { cash, wallet, udhaar, mixed, qist }

/// Document lifecycle. Posted documents are immutable; a correction creates
/// a `reversal` document pointing back via `reversesId`, and the original
/// becomes `reversed`.
enum DocStatus { posted, reversed, reversal }

enum PaymentDirection { incoming, outgoing }

enum StockMoveType {
  opening,
  purchase,
  sale,
  saleReturn,
  purchaseReturn,
  adjustment,
  repairPart,
  usedPurchase,
  qistRecovery,
}

enum ImeiStatus { inStock, sold, returned, inRepair, writtenOff }

enum AccountType { asset, liability, equity, income, expense }

enum RepairStatus { received, diagnosing, waitingParts, ready, delivered, returnedUnrepaired }

enum QistFrequency { weekly, monthly }

enum QistPlanStatus { active, completed, cancelled }

/// `overdue` is never stored; it is derived from due date (spec 8.1).
enum QistRowStatus { due, partial, paid }

/// What a payment allocation settles.
enum AllocDocType { sale, purchase, qist, repair }

/// Where an allocation came from.
enum AllocSource { payment, saleReturn, purchaseReturn }

enum AdjustmentReason { damaged, lost, found, countCorrection }

enum ConditionGrade { a, b, c }

enum LicenseStatus { active, transferred, invalid }

enum RepairPartAction { issued, returned }
