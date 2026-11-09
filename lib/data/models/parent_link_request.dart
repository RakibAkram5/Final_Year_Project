/// A parent's request to be linked to an existing student. The parent submits
/// the child's identifying details; an academy admin verifies and approves,
/// which creates the actual parent↔student link. Mirrors the backend
/// `ParentLinkRequest` model (see taleemplus_backend/src/controllers/userController.js).
class ParentLinkRequest {
  final String id;
  final String childName;
  final String? childEmail;
  final String? rollNumber;
  final String status; // PENDING | APPROVED | REJECTED
  final String? note;
  final DateTime? createdAt;
  final DateTime? decidedAt;

  /// Admin-only context (null in the parent's own view).
  final LinkRequestParty? parent;

  /// The student the backend auto-matched, shown to the admin for verification
  /// before approving. Null when no single unambiguous match was found.
  final LinkRequestParty? matchedStudent;

  const ParentLinkRequest({
    required this.id,
    required this.childName,
    required this.status,
    this.childEmail,
    this.rollNumber,
    this.note,
    this.createdAt,
    this.decidedAt,
    this.parent,
    this.matchedStudent,
  });

  bool get isPending => status == 'PENDING';
  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED';

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory ParentLinkRequest.fromJson(Map<String, dynamic> json) {
    return ParentLinkRequest(
      id: json['id'].toString(),
      childName: (json['childName'] ?? '').toString(),
      childEmail: json['childEmail']?.toString(),
      rollNumber: json['rollNumber']?.toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      note: json['note']?.toString(),
      createdAt: _date(json['createdAt']),
      decidedAt: _date(json['decidedAt']),
      parent: json['parent'] is Map
          ? LinkRequestParty.fromJson(Map<String, dynamic>.from(json['parent']))
          : null,
      matchedStudent: json['matchedStudent'] is Map
          ? LinkRequestParty.fromJson(
              Map<String, dynamic>.from(json['matchedStudent']))
          : null,
    );
  }
}

/// A minimal person summary (parent or matched student) returned with an
/// admin's view of a link request.
class LinkRequestParty {
  final String id;
  final String? fullName;
  final String? email;
  final String? phoneNumber;
  final String? rollNumber;
  final String? studentCode;

  const LinkRequestParty({
    required this.id,
    this.fullName,
    this.email,
    this.phoneNumber,
    this.rollNumber,
    this.studentCode,
  });

  factory LinkRequestParty.fromJson(Map<String, dynamic> json) {
    return LinkRequestParty(
      id: json['id'].toString(),
      fullName: json['fullName']?.toString(),
      email: json['email']?.toString(),
      phoneNumber: json['phoneNumber']?.toString(),
      rollNumber: json['rollNumber']?.toString(),
      studentCode: json['studentCode']?.toString(),
    );
  }
}
