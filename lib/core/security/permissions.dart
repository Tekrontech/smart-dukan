import '../domain/enums.dart';

/// What each role may do (spec Section 9).
///
/// Owner: everything. Manager: no settings, no licence, no deleting masters.
/// Cashier: sales, payments in, view stock; no cost prices, profit or
/// reports. Technician: repair jobs only.
class Permissions {
  const Permissions(this.role);

  final UserRole role;

  bool get _owner => role == UserRole.owner;
  bool get _mgr => role == UserRole.owner || role == UserRole.manager;

  bool get sell => role != UserRole.technician;
  bool get receivePayment => role != UserRole.technician;
  bool get viewStock => role != UserRole.technician;
  bool get viewKhata => role != UserRole.technician;
  bool get purchase => _mgr;
  bool get makePayment => _mgr;
  bool get expenses => _mgr;
  bool get editProducts => _mgr;
  bool get editParties => role != UserRole.technician;
  bool get seeCost => _mgr;
  bool get seeProfit => _mgr;
  bool get reports => _mgr;
  bool get cashClosing => role != UserRole.technician;
  bool get repairs => true;
  bool get qist => _mgr || role == UserRole.cashier;
  bool get usedPhones => _mgr;
  bool get viewCnic => _mgr;
  bool get deleteMasters => _owner;
  bool get settings => _owner;
  bool get license => _owner;
  bool get staff => _owner;
  bool get backup => _owner;
}
