class NotificationModel {
  final String id;
  final String academyId;
  final String recipientId; // UID of the user who should see this
  final String title;
  final String message;
  final String
      type; // 'approval', 'fee', 'attendance', 'result', 'announcement'
  final bool isRead;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.academyId,
    required this.recipientId,
    required this.title,
    required this.message,
    required this.type,
    this.isRead = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'academy_id': academyId,
      'recipient_id': recipientId,
      'title': title,
      'message': message,
      'type': type,
      'is_read': isRead,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  static DateTime _parseDate(dynamic val) {
    if (val == null) return DateTime.now();
    if (val is DateTime) return val;
    if (val is String) {
      final parsed = DateTime.tryParse(val);
      if (parsed != null) return parsed;
    }
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    return DateTime.now();
  }

  factory NotificationModel.fromMap(String id, Map<String, dynamic> map) {
    final rawCreatedAt = map['created_at'] ?? map['createdAt'];
    return NotificationModel(
      id: id.isNotEmpty ? id : (map['id'] ?? '').toString(),
      academyId: (map['academy_id'] ?? map['academyId'] ?? '').toString(),
      recipientId: (map['recipient_id'] ?? map['recipientId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      message: (map['message'] ?? '').toString(),
      type: (map['type'] ?? 'general').toString(),
      isRead: map['is_read'] ?? map['isRead'] ?? false,
      createdAt: _parseDate(rawCreatedAt),
    );
  }
}
