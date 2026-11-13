import 'dart:async';

/// In-process change notifications for REST-backed data.
///
/// The REST backend has no push channel, so repositories call
/// [DataChanges.notify] after a successful mutation and every [liveQuery]
/// watching the same topic re-fetches. This replaces the real-time behaviour
/// screens previously got from Firestore snapshots.
class DataChanges {
  DataChanges._();

  static final StreamController<String> _controller =
      StreamController<String>.broadcast();

  static void notify(String topic) => _controller.add(topic);

  static Stream<String> on(String topic) =>
      _controller.stream.where((t) => t == topic);
}

/// A stream that runs [fetch] when listened to and again whenever [topic]
/// is notified (and every [pollEvery], if given).
///
/// Fetch failures are delivered as stream *errors* (not empty lists), and the
/// stream keeps running so a later refresh can recover.
Stream<T> liveQuery<T>(
  String topic,
  Future<T> Function() fetch, {
  Duration? pollEvery,
}) {
  late StreamController<T> controller;
  StreamSubscription<String>? changes;
  Timer? poller;
  var running = false;
  var pending = false;

  Future<void> run() async {
    if (running) {
      pending = true;
      return;
    }
    running = true;
    try {
      do {
        pending = false;
        try {
          final value = await fetch();
          if (!controller.isClosed) controller.add(value);
        } catch (error, stack) {
          if (!controller.isClosed) controller.addError(error, stack);
        }
      } while (pending && !controller.isClosed);
    } finally {
      running = false;
    }
  }

  controller = StreamController<T>(
    onListen: () {
      run();
      changes = DataChanges.on(topic).listen((_) => run());
      if (pollEvery != null) {
        poller = Timer.periodic(pollEvery, (_) => run());
      }
    },
    onCancel: () async {
      poller?.cancel();
      await changes?.cancel();
    },
  );
  return controller.stream;
}

/// Topic names shared by repositories and services.
abstract final class DataTopics {
  static const classSections = 'class_sections';
  static const classes = 'classes';
  static const classReports = 'class_reports';
  static const academicStructure = 'academic_structure';
  static const timetable = 'timetable';
  static const announcements = 'announcements';
  static const notifications = 'notifications';
  static const resources = 'resources';
  static const queries = 'queries';
  static const quizzes = 'quizzes';
  static const quizSubmissions = 'quiz_submissions';
  static const marks = 'marks';
  static const ocrDocuments = 'ocr_documents';
  static const users = 'users';
}
