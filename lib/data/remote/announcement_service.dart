import '../models/announcement.dart';
import 'api_client.dart';
import 'live_query.dart';

/// Announcements over REST (`/announcements`). The server returns only the
/// announcements visible to the caller's role within their academy.
class AnnouncementService {
  final ApiClient _api = ApiClient();

  Future<void> create({
    required String title,
    required String message,
    required List<String> targetRoles,
    required String createdByUid,
    required String createdByName,
    required String academyId,
  }) async {
    await _api.post('/announcements', {
      'title': title.trim(),
      'message': message.trim(),
      'targetRoles': targetRoles,
    });
    DataChanges.notify(DataTopics.announcements);
  }

  Future<void> update({
    required String id,
    required String title,
    required String message,
    required List<String> targetRoles,
  }) async {
    await _api.put('/announcements/$id', {
      'title': title.trim(),
      'message': message.trim(),
      'targetRoles': targetRoles,
    });
    DataChanges.notify(DataTopics.announcements);
  }

  Future<void> delete(String id) async {
    await _api.delete('/announcements/$id');
    DataChanges.notify(DataTopics.announcements);
  }

  Future<List<Announcement>> _fetch() async {
    final res = await _api.get('/announcements');
    final list = (res as List)
        .map((d) => Announcement.fromMap(
            (d['id'] ?? '').toString(), Map<String, dynamic>.from(d as Map)))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Admin: every announcement in the academy.
  Stream<List<Announcement>> watchAll(String academyId) =>
      liveQuery(DataTopics.announcements, _fetch,
          pollEvery: const Duration(minutes: 2));

  /// Teacher/Student/Parent: announcements targeted at [role].
  Stream<List<Announcement>> watchForRole(String role, String academyId) =>
      liveQuery(DataTopics.announcements, () async {
        final all = await _fetch();
        return all.where((a) => a.isForRole(role)).toList();
      }, pollEvery: const Duration(minutes: 2));
}
