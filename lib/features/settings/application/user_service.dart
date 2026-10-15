import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/accounting/posting.dart';
import '../../../core/db/app_database.dart';
import '../../../core/security/pin_service.dart';
import '../../../core/utils/ids.dart';

/// Owner and staff accounts with their PINs (spec Section 9).
class UserService {
  UserService(this.db, {this.businessId = '', this.actorId});

  final AppDatabase db;
  final String businessId;
  final String? actorId;

  Future<List<AppUser>> activeUsers() =>
      (db.select(db.users)..where((u) => u.isActive.equals(true))..orderBy([(u) => OrderingTerm.asc(u.createdAt)])).get();

  Stream<List<AppUser>> watchUsers() =>
      (db.select(db.users)..orderBy([(u) => OrderingTerm.asc(u.createdAt)])).watch();

  Future<String> createUser({required String name, required UserRole role, required String pin}) async {
    if (name.trim().isEmpty) throw const PostingException(PostingError.invalidInput, 'name');
    final hash = await PinService.hash(pin);
    final others = await activeUsers();
    for (final u in others) {
      if (await PinService.verify(pin, u.pinHash)) {
        throw const PostingException(PostingError.invalidInput, 'pin_in_use');
      }
    }
    final now = DateTime.now();
    final id = newId();
    await db.into(db.users).insert(UsersCompanion.insert(
          id: id,
          businessId: businessId,
          createdAt: now,
          updatedAt: now,
          createdBy: Value(actorId),
          name: name.trim(),
          role: role,
          pinHash: hash,
        ));
    await _audit(id, 'create', {'name': name, 'role': role.name});
    return id;
  }

  Future<void> changePin(String userId, String newPin) async {
    final hash = await PinService.hash(newPin);
    await (db.update(db.users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(pinHash: Value(hash), updatedAt: Value(DateTime.now())));
    await _audit(userId, 'update_master', {'pin': 'changed'});
  }

  Future<void> update(String userId, {String? name, UserRole? role, bool? active}) async {
    final user = await (db.select(db.users)..where((u) => u.id.equals(userId))).getSingle();
    if (user.role == UserRole.owner && ((role != null && role != UserRole.owner) || active == false)) {
      final owners = (await activeUsers()).where((u) => u.role == UserRole.owner).length;
      if (owners <= 1) throw const PostingException(PostingError.invalidInput, 'last_owner');
    }
    await (db.update(db.users)..where((u) => u.id.equals(userId))).write(UsersCompanion(
      name: name == null ? const Value.absent() : Value(name.trim()),
      role: role == null ? const Value.absent() : Value(role),
      isActive: active == null ? const Value.absent() : Value(active),
      updatedAt: Value(DateTime.now()),
    ));
    await _audit(userId, 'update_master', {'role': role?.name, 'active': active});
  }

  Future<bool> verify(AppUser user, String pin) => PinService.verify(pin, user.pinHash);

  /// True if [pin] belongs to any active owner (for owner-PIN gates).
  Future<AppUser?> ownerForPin(String pin) async {
    for (final u in await activeUsers()) {
      if (u.role == UserRole.owner && await PinService.verify(pin, u.pinHash)) return u;
    }
    return null;
  }

  Future<void> recordLogin(String userId) => _audit(userId, 'login', null);

  Future<void> _audit(String entityId, String action, Map<String, Object?>? after) async {
    final now = DateTime.now();
    await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
          id: newId(),
          businessId: businessId,
          createdAt: now,
          updatedAt: now,
          createdBy: Value(actorId),
          entity: 'user',
          entityId: entityId,
          action: action,
          afterJson: Value(after == null ? null : jsonEncode(after)),
          userId: Value(actorId ?? entityId),
        ));
  }
}
