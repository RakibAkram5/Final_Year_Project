import '../models/notification_model.dart';
import 'api_client.dart';
import 'live_query.dart';

class NotificationService {
  final ApiClient _api = ApiClient();

  /// Send a notification to a specific user
  Future<void> send({
    required String academyId,
    required String recipientId,
    required String title,
    required String message,
    required String type,
  }) async {
    await _api.post('/notifications', {
      'recipientId': recipientId,
      'title': title,
      'message': message,
      'type': type,
    });
    DataChanges.notify(DataTopics.notifications);
  }

  Future<List<NotificationModel>> fetchForCurrentUser() async {
    final res = await _api.get('/notifications');
    return (res as List)
        .map((d) => NotificationModel.fromMap(
            (d['id'] ?? '').toString(), Map<String, dynamic>.from(d as Map)))
        .toList();
  }

  /// The signed-in user's notifications, refreshed after local changes and
  /// polled every minute so new approvals/announcements show up.
  Stream<List<NotificationModel>> watchForUser(
          String userId, String academyId) =>
      liveQuery(DataTopics.notifications, fetchForCurrentUser,
          pollEvery: const Duration(minutes: 1));

  /// Sends the same notification to many recipients
  Future<void> sendToMany({
    required String academyId,
    required List<String> recipientIds,
    required String title,
    required String message,
    required String type,
  }) async {
    for (final recipientId in recipientIds) {
      await send(
        academyId: academyId,
        recipientId: recipientId,
        title: title,
        message: message,
        type: type,
      );
    }
  }

  Future<void> markAsRead(String id) async {
    await _api.put('/notifications/$id/read', {});
    DataChanges.notify(DataTopics.notifications);
  }

  Future<void> markAllAsRead(String userId, String academyId) async {
    await _api.put('/notifications/read-all', {});
    DataChanges.notify(DataTopics.notifications);
  }
}
