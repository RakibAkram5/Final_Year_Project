import '../models/timetable_slot.dart';
import 'api_client.dart';
import 'live_query.dart';

/// Timetable slots over REST (`/timetable`). The server scopes results by
/// role: admins see the academy, teachers their own slots, students and
/// parents the classes they (or their children) are enrolled in.
class TimetableService {
  final ApiClient _api = ApiClient();

  Future<void> createSlot(TimetableSlot slot) async {
    await _api.post('/timetable', slot.toMap());
    DataChanges.notify(DataTopics.timetable);
  }

  Future<void> updateSlot(TimetableSlot slot) async {
    await _api.put('/timetable/${slot.id}', slot.toMap());
    DataChanges.notify(DataTopics.timetable);
  }

  Future<void> deleteSlot(String id) async {
    await _api.delete('/timetable/$id');
    DataChanges.notify(DataTopics.timetable);
  }

  Future<List<TimetableSlot>> _fetch(String path) async {
    final res = await _api.get(path);
    final list = (res as List)
        .map((item) => TimetableSlot.fromMap((item['id'] ?? '').toString(),
            Map<String, dynamic>.from(item as Map)))
        .toList();
    _sortByDayThenTime(list);
    return list;
  }

  /// Admin: every slot in the academy.
  Stream<List<TimetableSlot>> watchAll(String academyId) =>
      liveQuery(DataTopics.timetable, () => _fetch('/timetable'));

  /// Teacher: only their own assigned slots.
  Stream<List<TimetableSlot>> watchForTeacher(
          String teacherId, String academyId) =>
      liveQuery(
          DataTopics.timetable,
          () =>
              _fetch('/timetable?teacherId=${Uri.encodeComponent(teacherId)}'));

  /// Student/Parent: every slot across the given subject classes.
  Stream<List<TimetableSlot>> watchForClassIds(
      List<String> classIds, String academyId) {
    if (classIds.isEmpty) return Stream.value(const <TimetableSlot>[]);
    final query = classIds.map(Uri.encodeComponent).join(',');
    return liveQuery(
        DataTopics.timetable, () => _fetch('/timetable?classIds=$query'));
  }

  /// One-time fetch of every visible slot on a given day of the week
  /// (1 = Monday … 7 = Sunday).
  Future<List<TimetableSlot>> getSlotsForDay(String academyId, int dayOfWeek) =>
      _fetch('/timetable?dayOfWeek=$dayOfWeek');

  /// Deletes every slot referencing a class that is being removed.
  Future<void> deleteForClass(String classId, String academyId) async {
    final slots =
        await _fetch('/timetable?classIds=${Uri.encodeComponent(classId)}');
    for (final slot in slots) {
      await _api.delete('/timetable/${slot.id}');
    }
    if (slots.isNotEmpty) DataChanges.notify(DataTopics.timetable);
  }

  void _sortByDayThenTime(List<TimetableSlot> list) {
    list.sort((a, b) {
      final dayCompare = a.dayOfWeek.compareTo(b.dayOfWeek);
      if (dayCompare != 0) return dayCompare;
      return a.startMinutes.compareTo(b.startMinutes);
    });
  }
}
