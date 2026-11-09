import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../models/app_user.dart';
import 'api_client.dart';
import 'live_query.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class AcademyLookupResult {
  final String uid;
  final String academyName;
  AcademyLookupResult(this.uid, this.academyName);
}

/// Authentication service backed by Node.js + Express REST API, providing complete compatibility with all Flutter providers and screens.
class AuthService {
  final ApiClient _api = ApiClient();

  static const String _cachedProfileKey = 'tp_cached_profile_v1';

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;

  // Retained for older screens; session restore uses the backend token.
  dynamic get firebaseUser => null;

  Future<bool> hasStoredSession() async =>
      (await _api.getAccessToken())?.isNotEmpty ?? false;

  /// Returns the last approved profile cached locally so the first screen can
  /// render without waiting for the network.
  Future<AppUser?> getCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedProfileKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _mapApiUser(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Corrupt cache: drop it and fall back to the network path.
      await prefs.remove(_cachedProfileKey);
    }
    return null;
  }

  Future<void> clearCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedProfileKey);
  }

  Future<void> _cacheUser(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cachedProfileKey,
      jsonEncode(_userToApiJson(user)),
    );
  }

  Map<String, dynamic> _userToApiJson(AppUser user) => {
        'id': user.uid,
        'fullName': user.fullName,
        'email': user.email,
        'phoneNumber': user.phoneNumber,
        'role': user.role.name,
        'accountStatus': user.accountStatus,
        'academyId': user.academyId,
        'academyName': user.academyName,
        'academyAddress': user.academyAddress,
        'academyPhone': user.academyPhone,
        'academyLogo': user.academyLogo,
        'academyLatitude': user.academyLocation?.latitude,
        'academyLongitude': user.academyLocation?.longitude,
        'academyLocationLabel': user.academyLocation?.label,
        'academyCode': user.academyCode,
        'assignedSections': user.assignedSections,
        'linkedChildren': user.linkedChildren,
        'studentCode': user.studentCode,
        'rollNumber': user.rollNumber,
        'subject': user.subject,
        'extraInfo': user.extraInfo,
        'joiningDate': user.joiningDate?.toUtc().toIso8601String(),
        'createdAt': user.createdAt?.toUtc().toIso8601String(),
      };

  Future<AppUser> signUp({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String password,
    required UserRole role,
    String? academyName,
    String? academyId,
    String? academyCode,
    String? academyAddress,
    String? academyPhone,
    String? securityQuestion,
    String? securityAnswer,
  }) async {
    try {
      if (role == UserRole.admin) {
        final res = await _api.post(
            '/auth/register-admin',
            {
              'email': email.trim(),
              'password': password,
              'fullName': fullName.trim(),
              'academyName': academyName ?? 'TaleemPlus Academy',
              'academyAddress': academyAddress ?? '',
              'academyPhone': academyPhone ?? phoneNumber,
            },
            withAuth: false);

        final userData = res['user'];
        final tokens = res['tokens'];
        if (tokens != null) {
          await _api.setTokens(tokens['accessToken'], tokens['refreshToken']);
        }
        _currentUser = _mapApiUser(userData);
        await _cacheUser(_currentUser!);
        return _currentUser!;
      } else {
        final res = await _api.post(
            '/auth/register-user',
            {
              'email': email.trim(),
              'password': password,
              'fullName': fullName.trim(),
              'role': role.name,
              'academyCode': academyCode ?? academyId ?? '',
              'phoneNumber': phoneNumber.trim(),
            },
            withAuth: false);

        final userData = res['user'];
        return _mapApiUser(userData);
      }
    } catch (e) {
      throw AuthException(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<AppUser> signIn(String email, String password) async {
    try {
      final res = await _api.post(
          '/auth/login',
          {
            'email': email.trim(),
            'password': password,
          },
          withAuth: false);

      final userData = res['user'];
      final tokens = res['tokens'];
      if (tokens != null) {
        await _api.setTokens(tokens['accessToken'], tokens['refreshToken']);
      }
      _currentUser = _mapApiUser(userData);
      await _cacheUser(_currentUser!);
      return _currentUser!;
    } catch (e) {
      throw AuthException(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Fetches the authoritative profile. Throws on network/transport failure so
  /// callers can keep a cached session instead of treating an outage as a
  /// sign-out. Pass [timeout] for bootstrap calls that must not block startup.
  Future<AppUser?> getCurrentUserProfile({Duration? timeout}) async {
    final res = await _api.get('/auth/me', timeout: timeout);
    _currentUser = _mapApiUser(Map<String, dynamic>.from(res as Map));
    await _cacheUser(_currentUser!);
    return _currentUser;
  }

  Future<void> signOut() async {
    try {
      final refresh = await _api.getStoredRefreshToken();
      await _api.post('/auth/logout', {'refreshToken': refresh},
          withAuth: false);
    } catch (_) {}
    await _api.clearTokens();
    await clearCachedUser();
    _currentUser = null;
  }

  Future<List<AppUser>> getPendingUsers(String academyId) async {
    final res = await _api.get('/users/pending');
    return (res as List)
        .map((item) => _mapApiUser(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<void> approveUser(String uid) async {
    await _api.put('/users/$uid/approve', {});
  }

  Future<void> rejectUser(String uid) async {
    await _api.put('/users/$uid/reject', {});
  }

  /// Deactivates an account: the user can no longer sign in, but their
  /// attendance, fee and marks history is preserved.
  Future<void> deactivateUser(String uid) async {
    await _api.put('/users/$uid/deactivate', {});
  }

  Future<void> reactivateUser(String uid) async {
    await _api.put('/users/$uid/reactivate', {});
  }

  /// Admin-only: sets a new password for a member of the same academy and
  /// signs them out everywhere.
  Future<void> adminResetPassword(String uid, String newPassword) async {
    await _api.put('/users/$uid/password', {'newPassword': newPassword});
  }

  Future<List<AppUser>> getUsersByRole(dynamic arg1, dynamic arg2) async {
    try {
      UserRole role;
      if (arg1 is UserRole) {
        role = arg1;
      } else {
        role = arg2 is UserRole
            ? arg2
            : UserRoleX.fromValue((arg2 ?? '').toString().toLowerCase());
      }
      final res = await _api.get('/users/by-role?role=${role.name}');
      return (res as List)
          .map((item) => _mapApiUser(Map<String, dynamic>.from(item as Map)))
          .toList();
    } on ApiException {
      rethrow;
    }
  }

  Future<List<AppUser>> getApprovedByRole(dynamic arg1, dynamic arg2) async {
    return getUsersByRole(arg1, arg2);
  }

  Future<void> linkChild(
      {required String parentId, required String studentId}) async {
    await _api.post('/users/link-child', {
      'parentId': parentId,
      'studentId': studentId,
    });
    DataChanges.notify(DataTopics.users);
  }

  Future<void> addLinkedChild(String parentUid, String studentUid) async {
    await linkChild(parentId: parentUid, studentId: studentUid);
  }

  Future<void> removeLinkedChild(String parentUid, String studentUid) async {
    final isSelf = _currentUser?.uid == parentUid;
    await _api.delete(isSelf
        ? '/users/link-child/$studentUid'
        : '/users/link-child/$studentUid?parentId=${Uri.encodeComponent(parentUid)}');
    if (isSelf && _currentUser != null) {
      _currentUser = _currentUser!.copyWith(
        linkedChildren: _currentUser!.linkedChildren
            .where((id) => id != studentUid)
            .toList(),
      );
      await _cacheUser(_currentUser!);
    }
    DataChanges.notify(DataTopics.users);
  }

  /// Returns the profile for [uid], or null if it does not exist or is not
  /// visible to the caller. Never substitutes the signed-in user's profile.
  Future<AppUser?> getProfile(String uid) async {
    if (_currentUser?.uid == uid) return _currentUser;
    try {
      final res = await _api.get('/users/$uid');
      if (res is Map) return _mapApiUser(Map<String, dynamic>.from(res));
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 403) return null;
      rethrow;
    }
    return null;
  }

  Future<List<AppUser>> getProfilesByIds(List<String> uids) async {
    final ids = uids.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return [];
    final res = await _api.post('/users/profiles', {'ids': ids});
    return (res as List)
        .map((item) => _mapApiUser(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<void> updateAcademyProfile({
    String? academyId,
    String? academyName,
    String? academyAddress,
    String? academyPhone,
    String? academyLogo,
    String? name,
    String? address,
    String? phone,
    String? uid,
  }) async {
    final data = <String, dynamic>{};
    if (name != null || academyName != null) {
      data['name'] = name ?? academyName;
    }
    if (address != null || academyAddress != null) {
      data['address'] = address ?? academyAddress;
    }
    if (phone != null || academyPhone != null) {
      data['phone'] = phone ?? academyPhone;
    }
    if (academyLogo != null) data['logo'] = academyLogo;
    if (data.isEmpty) return;
    final response = await _api.put('/auth/academy', data);
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(
        academyName: response['academyName'] as String?,
        academyAddress: response['academyAddress'] as String?,
        academyPhone: response['academyPhone'] as String?,
        academyLogo: response['academyLogo'] as String?,
      );
      await _cacheUser(_currentUser!);
    }
  }

  /// Saves (or clears, when [location] is null) the academy location and
  /// optionally its street address. Admin only; the server validates ranges.
  Future<AcademyLocation?> saveAcademyLocation(AcademyLocation? location,
      {String? address}) async {
    final response = await _api.put('/auth/academy', {
      'latitude': location?.latitude,
      'longitude': location?.longitude,
      if (location != null) 'locationLabel': location.label,
      if (address != null) 'address': address,
    });
    final saved = AcademyLocation.tryParse(response['academyLatitude'],
        response['academyLongitude'], response['academyLocationLabel']);
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(
        academyLocation: saved,
        clearAcademyLocation: saved == null,
        academyAddress: response['academyAddress'] as String?,
      );
      await _cacheUser(_currentUser!);
    }
    return saved;
  }

  Future<void> directUpdatePassword(String newPassword,
      {required String currentPassword}) async {
    await _api.put('/auth/password', {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  Future<bool> verifyPassword(String password) async {
    try {
      final result =
          await _api.post('/auth/verify-password', {'password': password});
      return result is Map && result['valid'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Server-side uniqueness check (case-insensitive, per academy). Throws
  /// on network errors rather than reporting a roll number as free.
  Future<bool> isRollNumberTaken(String academyId, String rollNumber,
      {String? excludeUid}) async {
    final roll = rollNumber.trim();
    if (roll.isEmpty) return false;
    final query = StringBuffer(
        '/users/roll-number-available?rollNumber=${Uri.encodeComponent(roll)}');
    if (excludeUid != null && excludeUid.isNotEmpty) {
      query.write('&excludeId=${Uri.encodeComponent(excludeUid)}');
    }
    final res = await _api.get(query.toString());
    return !(res is Map && res['available'] == true);
  }

  Future<void> updateUserProfile({
    AppUser? user,
    String? uid,
    String? fullName,
    String? phoneNumber,
    String? extraInfo,
    String? subject,
    String? rollNumber,
    DateTime? joiningDate,
    List<String>? sections,
  }) async {
    final targetId = uid ?? user?.uid ?? _currentUser?.uid;
    if (targetId == null) {
      throw AuthException('No user selected to update.');
    }
    final isOwn = targetId == _currentUser?.uid;
    final path = isOwn ? '/users/me' : '/users/$targetId';
    final payload = <String, dynamic>{};
    if (fullName != null) payload['fullName'] = fullName;
    if (phoneNumber != null) payload['phoneNumber'] = phoneNumber;
    if (extraInfo != null) payload['extraInfo'] = extraInfo;
    if (subject != null) payload['subject'] = subject;
    if (rollNumber != null) payload['rollNumber'] = rollNumber;
    if (joiningDate != null) {
      payload['joiningDate'] = joiningDate.toUtc().toIso8601String();
    }
    if (sections != null) payload['assignedSections'] = sections;

    if (payload.isEmpty) return;
    final response = await _api.put(path, payload);
    if (isOwn && _currentUser != null && response is Map) {
      _currentUser = _mapApiUser(Map<String, dynamic>.from(response));
      await _cacheUser(_currentUser!);
    }
    DataChanges.notify(DataTopics.users);
  }

  Future<AppUser> adminCreateUser({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
    required UserRole role,
    required String academyId,
    List<String>? assignedSections,
    List<String>? sections,
    String? subject,
    String? rollNumber,
    DateTime? joiningDate,
    String? extraInfo,
  }) async {
    final payload = <String, dynamic>{
      'email': email,
      'password': password,
      'fullName': fullName,
      'role': role.name,
      'phoneNumber': phoneNumber,
      'assignedSections': assignedSections ?? sections ?? [],
    };
    if (rollNumber != null) payload['rollNumber'] = rollNumber;
    if (subject != null) payload['subject'] = subject;
    if (extraInfo != null) payload['extraInfo'] = extraInfo;
    if (joiningDate != null) {
      payload['joiningDate'] = joiningDate.toUtc().toIso8601String();
    }

    final res = await _api.post('/users/create', payload);
    return _mapApiUser(Map<String, dynamic>.from(res as Map));
  }

  /// Returns {'question': ...} or null when the account has no recovery
  /// question configured.
  Future<Map<String, String>?> getSecurityQuestion(String email) async {
    try {
      final res = await _api.get(
          '/auth/security-question?email=${Uri.encodeComponent(email.trim())}',
          withAuth: false);
      final question = res is Map ? res['question']?.toString() : null;
      return (question == null || question.isEmpty)
          ? null
          : {'question': question};
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      throw AuthException(e.message);
    }
  }

  /// Resets the password after verifying the security answer server-side.
  /// Throws [AuthException] with the server's reason on failure.
  Future<void> resetPasswordWithSecurityAnswer({
    required String email,
    required String answer,
    required String newPassword,
  }) async {
    try {
      await _api.post(
          '/auth/reset-password',
          {
            'email': email.trim(),
            'securityAnswer': answer.trim(),
            'newPassword': newPassword,
          },
          withAuth: false);
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
  }

  /// There is no email transport on the REST backend, so this cannot send a
  /// reset link. It always throws with guidance instead of pretending.
  Future<void> sendPasswordReset(String email) async {
    throw AuthException(
        'Email reset links are not available. Set a security question from '
        'your profile, or ask your academy admin to reset your password.');
  }

  Future<AcademyLookupResult?> findAcademyByCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    try {
      final res = await _api.get(
          '/auth/academy-lookup?code=${Uri.encodeComponent(trimmed)}',
          withAuth: false);
      if (res is Map) {
        return AcademyLookupResult((res['code'] ?? trimmed).toString(),
            (res['name'] ?? '').toString());
      }
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      throw AuthException(e.message);
    }
  }

  /// Academy membership is assigned by the server and changing it requires
  /// the target academy's approval, so a user cannot move themselves.
  /// Verifies the code and refreshes the profile if it already matches.
  Future<AppUser> relinkAcademy(String userId, String newAcademyCode) async {
    final current = await getCurrentUserProfile();
    if (current == null) throw AuthException('No active session found.');
    final code = newAcademyCode.trim().toUpperCase();
    if ((current.academyCode ?? '').toUpperCase() == code) return current;
    final academy = await findAcademyByCode(code);
    if (academy == null) throw AuthException('Invalid academy code.');
    throw AuthException(
        'Your account belongs to ${current.academyName ?? 'another academy'}. '
        'To join ${academy.academyName}, ask its admin to create an account '
        'for you or register again with that academy code.');
  }

  /// Emits the cached profile immediately, then the server copy, and again
  /// whenever user data changes locally (e.g. a child is linked).
  Stream<AppUser?> watchProfile(String uid) async* {
    if (_currentUser != null) yield _currentUser;
    yield* liveQuery(DataTopics.users, () => getCurrentUserProfile());
  }

  /// Exact (case-insensitive) email match within the caller's academy, or
  /// null. Never falls back to a different student.
  Future<AppUser?> findStudentByEmail(String email, String academyId) async {
    final target = email.trim().toLowerCase();
    if (target.isEmpty) return null;
    final res = await _api
        .get('/users/search?role=STUDENT&q=${Uri.encodeComponent(target)}');
    if (res is! List) return null;
    for (final item in res) {
      if ((item['email'] ?? '').toString().toLowerCase() == target) {
        return _mapApiUser(Map<String, dynamic>.from(item as Map));
      }
    }
    return null;
  }

  Future<void> saveSecurityQuestion({
    required String uid,
    required String email,
    required String question,
    required String answer,
  }) async {
    try {
      await _api.put('/auth/security-question', {
        'question': question.trim(),
        'answer': answer.trim(),
      });
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
  }

  Future<List<AppUser>> searchStudentsByName(String academyId, String query,
      {String? excludeUid}) async {
    if (query.trim().length < 2) return [];
    final res = await _api.get(
        '/users/search?role=STUDENT&q=${Uri.encodeComponent(query.trim())}');
    if (res is! List) return [];
    return res
        .map((item) => _mapApiUser(Map<String, dynamic>.from(item as Map)))
        .where((user) => user.uid != excludeUid)
        .toList();
  }

  AppUser _mapApiUser(Map<String, dynamic> json) {
    return AppUser(
      uid: json['id'] ?? json['uid'] ?? '',
      fullName: json['fullName'] ?? json['full_name'] ?? '',
      email: json['email'] ?? '',
      phoneNumber: json['phoneNumber'] ?? json['phone_number'] ?? '',
      role: UserRole.values.firstWhere(
        (e) =>
            e.name.toLowerCase() ==
            (json['role'] ?? 'student').toString().toLowerCase(),
        orElse: () => UserRole.student,
      ),
      accountStatus:
          (json['accountStatus'] ?? json['account_status'] ?? 'pending')
              .toString()
              .toLowerCase(),
      academyId: json['academyId'] ?? json['academy_id'] ?? '',
      academyName: json['academyName'] ?? json['academy_name'],
      academyAddress: json['academyAddress'] ?? json['academy_address'],
      academyPhone: json['academyPhone'] ?? json['academy_phone'],
      academyLogo: json['academyLogo'] ?? json['academy_logo'],
      academyLocation: AcademyLocation.tryParse(json['academyLatitude'],
          json['academyLongitude'], json['academyLocationLabel']),
      academyCode: json['academyCode'] ?? json['academy_code'],
      assignedSections: (json['assignedSections'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      linkedChildren: (json['linkedChildren'] as List?)
              ?.map((e) => (e is Map ? e['id'] : e).toString())
              .toList() ??
          [],
      studentCode:
          (json['studentCode'] ?? json['student_code'] ?? '').toString(),
      rollNumber: (json['rollNumber'] ?? json['roll_number'] ?? '').toString(),
      subject: (json['subject'] ?? '').toString(),
      extraInfo: (json['extraInfo'] ?? json['extra_info'])?.toString(),
      joiningDate:
          ApiClient.parseDate(json['joiningDate'] ?? json['joining_date']),
      createdAt: ApiClient.parseDate(json['createdAt'] ?? json['created_at']),
    );
  }
}
