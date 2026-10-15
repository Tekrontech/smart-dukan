import 'package:flutter/widgets.dart';

import '../domain/enums.dart';
import '../l10n/l10n.dart';

/// Localized names for domain enums.
extension EnumLabels on BuildContext {
  String methodLabel(PaymentMethod m) => switch (m) {
        PaymentMethod.cash => l10n.methodCash,
        PaymentMethod.bank => l10n.methodBank,
        PaymentMethod.jazzcash => l10n.methodJazzcash,
        PaymentMethod.easypaisa => l10n.methodEasypaisa,
      };

  String moveLabel(StockMoveType t) => switch (t) {
        StockMoveType.opening => l10n.mvOpening,
        StockMoveType.purchase => l10n.mvPurchase,
        StockMoveType.sale => l10n.mvSale,
        StockMoveType.saleReturn => l10n.mvSaleReturn,
        StockMoveType.purchaseReturn => l10n.mvPurchaseReturn,
        StockMoveType.adjustment => l10n.mvAdjustment,
        StockMoveType.repairPart => l10n.mvRepairPart,
        StockMoveType.usedPurchase => l10n.mvUsedPurchase,
        StockMoveType.qistRecovery => l10n.mvQistRecovery,
      };

  String imeiStatusLabel(ImeiStatus s) => switch (s) {
        ImeiStatus.inStock => l10n.imeiInStock,
        ImeiStatus.sold => l10n.imeiSold,
        ImeiStatus.returned => l10n.imeiReturned,
        ImeiStatus.inRepair => l10n.imeiInRepair,
        ImeiStatus.writtenOff => l10n.imeiWrittenOff,
      };

  String reasonLabel(AdjustmentReason r) => switch (r) {
        AdjustmentReason.damaged => l10n.reasonDamaged,
        AdjustmentReason.lost => l10n.reasonLost,
        AdjustmentReason.found => l10n.reasonFound,
        AdjustmentReason.countCorrection => l10n.reasonCount,
      };
}
