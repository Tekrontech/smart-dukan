import '../domain/enums.dart';

/// Built-in chart of accounts (spec Sections 7 and 8.1).
///
/// Accounts are referenced by [key] (`accounts.system_key`) in posting code,
/// never by id. Expense categories get their own `EXPENSE_<key>` accounts.
enum SysAccount {
  cash('CASH', '1001', 'Cash (Galla)', AccountType.asset),
  bank('BANK', '1002', 'Bank', AccountType.asset),
  wallet('WALLET', '1003', 'Mobile Wallet', AccountType.asset),
  ar('AR', '1100', 'Receivables (Lena)', AccountType.asset),
  inventory('INVENTORY', '1200', 'Inventory', AccountType.asset),
  ap('AP', '2000', 'Payables (Dena)', AccountType.liability),
  salesTaxPayable('SALES_TAX_PAYABLE', '2100', 'Sales Tax Payable', AccountType.liability),
  deferredMarkup('DEFERRED_MARKUP', '2200', 'Deferred Qist Markup', AccountType.liability),
  ownerCapital('OWNER_CAPITAL', '3000', 'Owner Capital', AccountType.equity),
  openingEquity('OPENING_EQUITY', '3100', 'Opening Balance Equity', AccountType.equity),
  sales('SALES', '4000', 'Sales', AccountType.income),
  salesReturns('SALES_RETURNS', '4010', 'Sales Returns', AccountType.income),
  discount('DISCOUNT', '4020', 'Discounts Given', AccountType.income),
  deliveryIncome('DELIVERY_INCOME', '4100', 'Delivery Income', AccountType.income),
  repairIncome('REPAIR_INCOME', '4200', 'Repair Income', AccountType.income),
  markupIncome('MARKUP_INCOME', '4300', 'Qist Markup Income', AccountType.income),
  cogs('COGS', '5000', 'Cost of Goods Sold', AccountType.expense),
  stockLoss('STOCK_LOSS', '5100', 'Stock Loss', AccountType.expense),
  inventoryAdjustment('INVENTORY_ADJUSTMENT', '5200', 'Inventory Adjustment', AccountType.expense),
  badDebt('BAD_DEBT', '5300', 'Bad Debt', AccountType.expense),
  cashOverShort('CASH_OVER_SHORT', '5400', 'Cash Over/Short', AccountType.expense);

  const SysAccount(this.key, this.code, this.name, this.type);

  final String key;
  final String code;
  final String name;
  final AccountType type;

  /// Account that receives money paid by [method].
  static SysAccount forMethod(PaymentMethod method) => switch (method) {
        PaymentMethod.cash => cash,
        PaymentMethod.bank => bank,
        PaymentMethod.jazzcash || PaymentMethod.easypaisa => wallet,
      };
}

/// Built-in expense categories (spec 5.7). Each gets account `EXPENSE_<key>`.
const List<String> builtInExpenseCategories = ['rent', 'bijli', 'salary', 'chai_pani', 'transport', 'other'];

String expenseAccountKey(String categoryKey) => 'EXPENSE_${categoryKey.toUpperCase()}';
