class FeeChallanModel {
  final String id;
  final String academyId; // NEW
  final String challanNumber;
  final String billingPeriod;
  final String studentId;
  final String studentCode;
  final String studentName;
  final String fatherName;
  final String classLabel;
  final String rollNumber;
  final DateTime issueDate;
  final DateTime dueDate;
  final double monthlyFee;
  final double admissionFee;
  final double examFee;
  final double transportFee;
  final double fine;
  final String status; // 'pending', 'paid', 'overdue'
  final DateTime createdAt;
  final DateTime updatedAt;

  FeeChallanModel({
    required this.id,
    required this.academyId, // NEW
    required this.challanNumber,
    this.billingPeriod = '',
    required this.studentId,
    this.studentCode = '',
    required this.studentName,
    required this.fatherName,
    required this.classLabel,
    required this.rollNumber,
    required this.issueDate,
    required this.dueDate,
    required this.monthlyFee,
    required this.admissionFee,
    required this.examFee,
    required this.transportFee,
    required this.fine,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  double get totalAmount =>
      monthlyFee + admissionFee + examFee + transportFee + fine;

  bool get isPaid => status == 'paid';

  /// A challan is overdue once its due *day* has fully passed in the
  /// device's local calendar (the due date itself is still payable).
  bool get isOverdue {
    if (isPaid) return false;
    if (status == 'overdue') return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return today.isAfter(dueDay);
  }

  /// First day of the month this challan bills for: the YYYY-MM billing
  /// period when present, otherwise the due date's month.
  DateTime get billingMonth {
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(billingPeriod);
    if (match != null) {
      return DateTime(int.parse(match.group(1)!), int.parse(match.group(2)!));
    }
    return DateTime(dueDate.year, dueDate.month);
  }

  /// 'pending' | 'paid' | 'overdue', with overdue derived from the due date.
  String get effectiveStatus =>
      isPaid ? 'paid' : (isOverdue ? 'overdue' : 'pending');

  Map<String, dynamic> toMap() {
    return {
      'academy_id': academyId,
      'challan_number': challanNumber,
      'billing_period': billingPeriod,
      'student_id': studentId,
      'student_code': studentCode,
      'student_name': studentName,
      'father_name': fatherName,
      'class_label': classLabel,
      'roll_number': rollNumber,
      'issue_date': issueDate.toUtc().toIso8601String(),
      'due_date': dueDate.toUtc().toIso8601String(),
      'monthly_fee': monthlyFee,
      'admission_fee': admissionFee,
      'exam_fee': examFee,
      'transport_fee': transportFee,
      'fine': fine,
      'total_amount': totalAmount,
      'status': status,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  /// Parses API dates (ISO-8601 strings, epoch millis, or DateTime) into the
  /// device's local time zone so month grouping and printed dates match the
  /// user's calendar. Returns null for missing or malformed values.
  static DateTime? tryParseDate(dynamic val) {
    if (val == null) return null;
    if (val is DateTime) return val.toLocal();
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val).toLocal();
    if (val is String && val.isNotEmpty) {
      return DateTime.tryParse(val)?.toLocal();
    }
    // Legacy Firestore Timestamp-like objects expose toDate().
    try {
      final date = (val as dynamic).toDate();
      if (date is DateTime) return date.toLocal();
    } catch (_) {}
    return null;
  }

  factory FeeChallanModel.fromMap(String id, Map<String, dynamic> map) {
    final created =
        tryParseDate(map['created_at'] ?? map['createdAt']) ?? DateTime.now();
    final issue =
        tryParseDate(map['issue_date'] ?? map['issueDate']) ?? created;
    final due = tryParseDate(map['due_date'] ?? map['dueDate']);
    if (due == null) {
      throw FormatException(
          'Fee challan ${map['id'] ?? id} has no valid due date.');
    }
    final updated =
        tryParseDate(map['updated_at'] ?? map['updatedAt']) ?? created;

    final rawStatus = (map['status'] ?? 'pending').toString().toLowerCase();

    return FeeChallanModel(
      id: id.isNotEmpty ? id : (map['id'] ?? '').toString(),
      academyId: (map['academy_id'] ?? map['academyId'] ?? '').toString(),
      challanNumber:
          (map['challan_number'] ?? map['challanNumber'] ?? '').toString(),
      billingPeriod:
          (map['billing_period'] ?? map['billingPeriod'] ?? '').toString(),
      studentId: (map['student_id'] ?? map['studentId'] ?? '').toString(),
      studentCode: (map['student_code'] ?? map['studentCode'] ?? '').toString(),
      studentName: (map['student_name'] ??
              map['studentName'] ??
              map['student_full_name'] ??
              '')
          .toString(),
      fatherName: (map['father_name'] ?? map['fatherName'] ?? '').toString(),
      classLabel: (map['class_label'] ?? map['classLabel'] ?? '').toString(),
      rollNumber: (map['roll_number'] ?? map['rollNumber'] ?? '').toString(),
      issueDate: issue,
      dueDate: due,
      monthlyFee: _num(map['monthly_fee'] ?? map['monthlyFee']),
      admissionFee: _num(map['admission_fee'] ?? map['admissionFee']),
      examFee: _num(map['exam_fee'] ?? map['examFee']),
      transportFee: _num(map['transport_fee'] ?? map['transportFee']),
      fine: _num(map['fine'] ?? map['fineAmount']),
      status: rawStatus,
      createdAt: created,
      updatedAt: updated,
    );
  }

  /// Prisma Decimal columns may serialize as strings.
  static double _num(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}
