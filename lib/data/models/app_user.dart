import '../remote/api_client.dart';
import '../../core/constants/app_constants.dart';

class AppUser {
  final String uid;
  final String fullName;
  final String email;
  final String phoneNumber;
  final UserRole role;
  final String accountStatus;
  final String? academyName; // For display
  final String? academyId; // For multi-tenancy scoping
  final String? academyAddress;
  final String? academyPhone;
  final String? academyLogo; // NEW: URL for branding
  final String? academyCode; // NEW: Short code for joining (e.g. SRS-101)
  final DateTime? createdAt;
  final DateTime? joiningDate; // NEW: When the user joined/was added
  final List<String>
      assignedSections; // NEW: Sections assigned (e.g. ['A', 'B'])
  final List<String> linkedChildren; // NEW: Child UIDs (for Parents)
  final String rollNumber; // NEW: unique within a student's class section
  final String studentCode;
  final String subject; // NEW: teacher's subject (separate from qualification)
  final String?
      extraInfo; // Role-specific note (qualification for teachers/relation for parents)

  const AppUser({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.role,
    this.accountStatus = 'active',
    this.academyName,
    this.academyId,
    this.academyAddress,
    this.academyPhone,
    this.academyLogo,
    this.academyCode,
    this.createdAt,
    this.joiningDate,
    this.assignedSections = const [],
    this.linkedChildren = const [],
    this.rollNumber = '',
    this.studentCode = '',
    this.subject = '',
    this.extraInfo,
  });

  bool get isApproved => accountStatus.toLowerCase() == 'active';
  bool get isPending => accountStatus.toLowerCase() == 'pending';
  bool get isRejected => accountStatus.toLowerCase() == 'rejected';

  Map<String, dynamic> toMap() {
    return {
      'user_id': uid,
      'full_name': fullName,
      'email': email,
      'phone_number': phoneNumber,
      'role': role.value,
      'account_status': accountStatus,
      'academy_name': academyName,
      'academy_id': academyId,
      'academy_address': academyAddress,
      'academy_phone': academyPhone,
      'academy_logo': academyLogo,
      'academy_code': academyCode,
      'sections': assignedSections,
      'linked_children': linkedChildren,
      'roll_number': rollNumber,
      'student_code': studentCode,
      'subject': subject,
      'extra_info': extraInfo,
      'created_at': createdAt != null
          ? createdAt!.toUtc().toIso8601String()
          : DateTime.now().toUtc().toIso8601String(),
      'joining_date': joiningDate != null
          ? joiningDate!.toUtc().toIso8601String()
          : DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    final ts = map['created_at'];
    return AppUser(
      uid: uid,
      fullName: (map['full_name'] ?? '') as String,
      email: (map['email'] ?? '') as String,
      phoneNumber: (map['phone_number'] ?? '') as String,
      role: UserRoleX.fromValue((map['role'] ?? 'student') as String),
      accountStatus: (map['account_status'] ?? 'active') as String,
      academyName: map['academy_name'] as String?,
      academyId: map['academy_id'] as String?,
      academyAddress: map['academy_address'] as String?,
      academyPhone: map['academy_phone'] as String?,
      academyLogo: map['academy_logo'] as String?,
      academyCode: map['academy_code'] as String?,
      createdAt: ApiClient.parseDate(ts),
      // Fall back to createdAt when no explicit joining date was recorded.
      joiningDate:
          ApiClient.parseDate(map['joining_date']) ?? ApiClient.parseDate(ts),
      assignedSections: (map['sections'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      linkedChildren: (map['linked_children'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      rollNumber: (map['roll_number'] ?? '') as String,
      studentCode: (map['student_code'] ?? '') as String,
      subject: (map['subject'] ?? '') as String,
      extraInfo: map['extra_info'] as String?,
    );
  }

  AppUser copyWith({
    String? uid,
    String? fullName,
    String? email,
    String? phoneNumber,
    UserRole? role,
    String? accountStatus,
    String? academyName,
    String? academyId,
    String? academyAddress,
    String? academyPhone,
    String? academyLogo,
    String? academyCode,
    DateTime? createdAt,
    DateTime? joiningDate,
    List<String>? assignedSections,
    List<String>? linkedChildren,
    String? rollNumber,
    String? studentCode,
    String? subject,
    String? extraInfo,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role ?? this.role,
      accountStatus: accountStatus ?? this.accountStatus,
      academyName: academyName ?? this.academyName,
      academyId: academyId ?? this.academyId,
      academyAddress: academyAddress ?? this.academyAddress,
      academyPhone: academyPhone ?? this.academyPhone,
      academyLogo: academyLogo ?? this.academyLogo,
      academyCode: academyCode ?? this.academyCode,
      createdAt: createdAt ?? this.createdAt,
      joiningDate: joiningDate ?? this.joiningDate,
      assignedSections: assignedSections ?? this.assignedSections,
      linkedChildren: linkedChildren ?? this.linkedChildren,
      rollNumber: rollNumber ?? this.rollNumber,
      studentCode: studentCode ?? this.studentCode,
      subject: subject ?? this.subject,
      extraInfo: extraInfo ?? this.extraInfo,
    );
  }
}
