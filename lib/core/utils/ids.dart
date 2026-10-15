import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// New UUID v7 (time-sortable, safe for a future sync) — spec Section 6.
String newId() => _uuid.v7();

/// Random UUID v4, used for the install ID (spec Section 2).
String newRandomId() => _uuid.v4();
