import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../data/models/academy_member.dart';
import '../data/models/app_user.dart'; // NEW
import '../data/repositories/member_repository.dart';
import '../data/remote/auth_service.dart';

class MemberProvider extends ChangeNotifier {
  final MemberRepository _repo;
  final AuthService _authService = AuthService();
  final _uuid = const Uuid();

  MemberProvider({MemberRepository? repo}) : _repo = repo ?? MemberRepository();

  List<AcademyMember> _members = [];
  Map<String, int> _counts = {'teacher': 0, 'student': 0, 'parent': 0};
  bool _loading = false;

  List<AcademyMember> get members => _members;
  Map<String, int> get counts => _counts;
  bool get loading => _loading;

  int get totalTeachers => _counts['teacher'] ?? 0;
  int get totalStudents => _counts['student'] ?? 0;
  int get totalParents => _counts['parent'] ?? 0;

  List<AcademyMember> byRole(String role) =>
      _members.where((m) => m.role == role).toList();

  Future<void> load(String academyId) async {
    _loading = true;
    notifyListeners();

    try {
      // Kick off the three independent role requests together; waiting for
      // them sequentially added two avoidable network round trips to startup.
      final rolesFuture = Future.wait([
        _authService.getApprovedByRole(academyId, UserRole.teacher),
        _authService.getApprovedByRole(academyId, UserRole.student),
        _authService.getApprovedByRole(academyId, UserRole.parent),
      ]);

      // 1. Fetch SQLite local members for THIS academy — sqflite has no web
      // implementation, so skip it there and rely on remote profiles alone.
      final sqliteMembers =
          kIsWeb ? <AcademyMember>[] : await _repo.getAll(academyId);

      // 2. Fetch remote approved users profiles for THIS academy
      final roles = await rolesFuture;
      final firestoreTeachers = roles[0];
      final firestoreStudents = roles[1];
      final firestoreParents = roles[2];

      // 3. Convert Firestore users to AcademyMember model for a unified list
      final List<AcademyMember> firestoreMembers = [
        ...firestoreTeachers.map((u) => _fromAppUser(u)),
        ...firestoreStudents.map((u) => _fromAppUser(u)),
        ...firestoreParents.map((u) => _fromAppUser(u)),
      ];

      // 4. Merge and Deduplicate by EMAIL
      final Map<String, AcademyMember> mergedMap = {};

      // Local SQLite members
      for (var m in sqliteMembers) {
        mergedMap[m.email.trim().toLowerCase()] = m;
      }

      // Firestore members (override SQLite if same email found)
      for (var m in firestoreMembers) {
        mergedMap[m.email.trim().toLowerCase()] = m;
      }

      _members = mergedMap.values.toList();
      _members.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // 5. Calculate counts from the merged list
      _counts = {
        'teacher': _members.where((m) => m.role == 'teacher').length,
        'student': _members.where((m) => m.role == 'student').length,
        'parent': _members.where((m) => m.role == 'parent').length,
      };
    } catch (e) {
      debugPrint("Error loading member counts: $e");
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  AcademyMember _fromAppUser(AppUser u) {
    return AcademyMember(
      id: u.uid,
      academyId: u.academyId ?? '',
      fullName: u.fullName,
      email: u.email,
      phone: u.phoneNumber,
      role: u.role.value,
      extra: u.extraInfo ?? '',
      subject: u.subject,
      rollNumber: u.rollNumber,
      status: u.accountStatus,
      createdAt: u.createdAt ?? DateTime.now(),
    );
  }

  Future<void> addMember({
    required String fullName,
    required String email,
    required String phone,
    required String role,
    required String academyId,
    String extra = '',
  }) async {
    // Duplicate check
    final emailLower = email.trim().toLowerCase();
    if (_members.any((m) => m.email.toLowerCase() == emailLower)) {
      throw Exception("A member with this email already exists.");
    }

    final member = AcademyMember(
      id: _uuid.v4(),
      academyId: academyId,
      fullName: fullName.trim(),
      email: email.trim(),
      phone: phone.trim(),
      role: role,
      extra: extra.trim(),
      createdAt: DateTime.now(),
    );
    if (!kIsWeb) {
      await _repo.add(member);
    }
    await load(academyId);
  }

  /// Removes a member from the active roster.
  ///
  /// Server accounts are *deactivated* (sign-in blocked, refresh tokens
  /// revoked) rather than deleted, so attendance, fee and marks history is
  /// preserved. Offline-only (SQLite) entries are removed locally.
  Future<void> removeMember(String id, String academyId) async {
    final remote = await _authService.getProfile(id);
    if (remote != null) {
      await _authService.deactivateUser(id);
    } else if (!kIsWeb) {
      await _repo.delete(id);
    } else {
      throw Exception('Member not found in this academy.');
    }
    await load(academyId);
  }
}
