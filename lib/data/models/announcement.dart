/// A broadcast message from an admin to one or more user roles.
class Announcement {
  final String id;
  final String academyId; // NEW
  final String title;
  final String message;
  final List<String> targetRoles;
  final String createdByUid;
  final String createdByName;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Announcement({
    required this.id,
    required this.academyId,
    required this.title,
    required this.message,
    required this.targetRoles,
    required this.createdByUid,
    required this.createdByName,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isForAll => targetRoles.any((r) => r.toLowerCase() == 'all');

  bool isForRole(String role) {
    if (isForAll) return true;
    final rLower = role.toLowerCase().trim();
    return targetRoles.any((tr) => tr.toLowerCase().trim() == rLower);
  }

  /// Human-readable badge like "Teachers", "Students & Parents", "Everyone".
  String get targetLabel {
    if (isForAll) return 'Everyone';
    final labels = targetRoles.map((r) {
      final rLower = r.toLowerCase().trim();
      switch (rLower) {
        case 'teacher':
          return 'Teachers';
        case 'student':
          return 'Students';
        case 'parent':
          return 'Parents';
        default:
          return r;
      }
    }).toList();
    if (labels.isEmpty) return 'None';
    if (labels.length == 1) return labels.first;
    if (labels.length == 2) return '${labels[0]} & ${labels[1]}';
    return labels.join(', ');
  }

  Map<String, dynamic> toMap() => {
        'academy_id': academyId,
        'title': title,
        'message': message,
        'target_roles': targetRoles,
        'created_by_uid': createdByUid,
        'created_by_name': createdByName,
        'created_at': createdAt.millisecondsSinceEpoch == 0
            ? DateTime.now().toUtc().toIso8601String()
            : createdAt.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  static DateTime _parseDate(dynamic val, [DateTime? fallback]) {
    if (val == null) return fallback ?? DateTime.now();
    if (val is DateTime) return val;
    if (val is String) {
      final parsed = DateTime.tryParse(val);
      if (parsed != null) return parsed;
    }
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    return fallback ?? DateTime.now();
  }

  factory Announcement.fromMap(String id, Map<String, dynamic> map) {
    final rolesRaw = map['target_roles'] ?? map['targetRoles'];
    final roles = (rolesRaw is List)
        ? rolesRaw.map((e) => e.toString()).toList()
        : <String>['all'];
    final rawCreatedAt = map['created_at'] ?? map['createdAt'];
    final rawUpdatedAt = map['updated_at'] ?? map['updatedAt'];

    return Announcement(
      id: id.isNotEmpty ? id : (map['id'] ?? '').toString(),
      academyId: (map['academy_id'] ?? map['academyId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      message: (map['message'] ?? '').toString(),
      targetRoles: roles,
      createdByUid:
          (map['created_by_uid'] ?? map['createdById'] ?? '').toString(),
      createdByName: (map['created_by_name'] ?? map['createdByName'] ?? 'Admin')
          .toString(),
      createdAt: _parseDate(rawCreatedAt),
      updatedAt: rawUpdatedAt != null ? _parseDate(rawUpdatedAt) : null,
    );
  }
}
