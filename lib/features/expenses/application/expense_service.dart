import 'package:drift/drift.dart';

import '../../../core/accounting/posting.dart';
import '../../../core/accounting/system_accounts.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/ids.dart';

/// Expenses (spec 5.7): Dr Expense:category, Cr Cash/Bank/Wallet.
class ExpenseService {
  ExpenseService(this.db, this.ctx) : posting = PostingService(db, ctx);

  final AppDatabase db;
  final BusinessCtx ctx;
  final PostingService posting;

  Future<String> create({
    required String categoryId,
    required Money amount,
    PaymentMethod method = PaymentMethod.cash,
    String? note,
    String? photoPath,
  }) {
    if (!amount.isPositive) throw const PostingException(PostingError.invalidAmount);
    return posting.run((p) async {
      final cat = await (db.select(db.expenseCategories)..where((c) => c.id.equals(categoryId))).getSingleOrNull();
      if (cat == null) throw const PostingException(PostingError.notFound, 'category');
      final account = await (db.select(db.accounts)..where((a) => a.id.equals(cat.accountId))).getSingle();
      final cashAcc = SysAccount.forMethod(method);
      final id = newId();
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
            id: id,
            businessId: p.businessId,
            createdAt: p.now,
            updatedAt: p.now,
            createdBy: Value(p.userId),
            categoryId: categoryId,
            date: p.now,
            amount: amount,
            method: method,
            accountId: await p.accountId(cashAcc.key),
            note: Value(note),
            photoPath: Value(photoPath),
            status: DocStatus.posted,
          ));
      p.drKey(account.systemKey, amount);
      p.cr(cashAcc, amount);
      await p.commit(date: p.now, sourceType: 'expense', sourceId: id, memo: cat.name);
      await p.audit('expense', id, 'create', after: {'amount': amount.paisa, 'category': cat.name});
      return id;
    });
  }

  Future<String> reverse(String expenseId) => posting.run((p) async {
        final e = await (db.select(db.expenses)..where((x) => x.id.equals(expenseId))).getSingleOrNull();
        if (e == null) throw const PostingException(PostingError.notFound);
        if (e.status != DocStatus.posted) throw const PostingException(PostingError.alreadyReversed);
        final revId = newId();
        await db.into(db.expenses).insert(ExpensesCompanion.insert(
              id: revId,
              businessId: p.businessId,
              createdAt: p.now,
              updatedAt: p.now,
              createdBy: Value(p.userId),
              categoryId: e.categoryId,
              date: p.now,
              amount: e.amount,
              method: e.method,
              accountId: e.accountId,
              note: const Value('Reversal'),
              status: DocStatus.reversal,
              reversesId: Value(e.id),
            ));
        await p.mirrorSource(sourceId: e.id, reversalId: revId, sourceType: 'expense');
        await (db.update(db.expenses)..where((x) => x.id.equals(e.id)))
            .write(ExpensesCompanion(status: const Value(DocStatus.reversed), updatedAt: Value(p.now)));
        await p.audit('expense', e.id, 'reverse');
        return revId;
      });
}
