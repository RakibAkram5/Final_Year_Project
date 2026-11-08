import 'dart:async';
import 'package:flutter/foundation.dart';

import '../data/models/app_user.dart';
import '../data/models/class_section.dart';
import '../data/repositories/class_section_repository.dart';

/// Loads the academy's class+section rosters from the REST API and
/// refreshes them after every create/enroll/delete.
class ClassSectionProvider extends ChangeNotifier {
  final ClassSectionRepository _repo;
  ClassSectionProvider({ClassSectionRepository? repo})
      : _repo = repo ?? ClassSectionRepository();

  List<ClassSectionEntity> _sections = [];
  bool _loading = true;
  String? _error;
  StreamSubscription? _sub;

  List<ClassSectionEntity> get sections => _sections;
  bool get loading => _loading;

  /// Last load error, or null after a successful load.
  String? get error => _error;

  List<ClassSectionEntity> forClass(String className) =>
      _sections.where((s) => s.className == className).toList();

  List<ClassSectionEntity> forClassAndProgram(
          String className, String program) =>
      _sections
          .where((s) => s.className == className && s.program == program)
          .toList();

  /// True if a section with this exact (class, program, section) already
  /// exists — sections aren't validated for duplicates otherwise.
  bool sectionExists({
    required String className,
    required String program,
    required String section,
  }) =>
      _sections.any((s) =>
          s.className == className &&
          s.program == program &&
          s.section.toLowerCase() == section.trim().toLowerCase());

  /// Start streaming all class sections for a specific academy.
  void listenAll(String academyId) {
    _sub?.cancel();
    _loading = true;
    notifyListeners();
    _sub = _repo.watchAll(academyId).listen(
      (list) {
        _sections = list;
        _loading = false;
        _error = null;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('Error loading class sections: $e');
        // Keep the last good roster visible; surface the failure.
        _error = e.toString();
        _loading = false;
        notifyListeners();
      },
    );
  }

  Future<void> createSection({
    required String academyId,
    required String className,
    String program = '',
    required String section,
  }) {
    return _repo.createSection(
      academyId: academyId,
      className: className,
      program: program,
      section: section,
    );
  }

  Future<void> updateEnrollment({
    required ClassSectionEntity section,
    required List<AppUser> students,
  }) {
    return _repo.updateEnrollment(section: section, students: students);
  }

  /// Adds a single student to a section (and its subject offerings).
  Future<void> enrollStudent({
    required ClassSectionEntity section,
    required String studentId,
    String? rollNumber,
  }) {
    return _repo.enrollStudent(
        sectionId: section.id, studentId: studentId, rollNumber: rollNumber);
  }

  Future<void> deleteSection(ClassSectionEntity section) {
    return _repo.deleteSection(section);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
