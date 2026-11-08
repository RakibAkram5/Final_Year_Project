import 'package:flutter/material.dart';

/// A single recurring weekly period in a class's schedule — e.g. "Class 9-B
/// has Physics with Teacher X every Monday 8:00-8:45 in Room 101, Fall 2026."
/// `classId`/`className`/`section`/`subject`/`teacherId`/`teacherName` are all
/// empty when [isBreak] is true (a break has no class or teacher attached).
class TimetableSlot {
  final String id;
  final String academyId;
  final bool isBreak;
  final String classId;
  final String className;
  final String section;
  final String subject;
  final String teacherId;
  final String teacherName;
  final int dayOfWeek; // DateTime.monday (1) .. DateTime.sunday (7)
  final int startMinutes; // minutes since midnight
  final int endMinutes;
  final String room;
  final String semester;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo; // null = ongoing, no end date
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TimetableSlot({
    required this.id,
    required this.academyId,
    this.isBreak = false,
    this.classId = '',
    this.className = '',
    this.section = '',
    this.subject = '',
    this.teacherId = '',
    this.teacherName = '',
    required this.dayOfWeek,
    required this.startMinutes,
    required this.endMinutes,
    this.room = '',
    this.semester = '',
    required this.effectiveFrom,
    this.effectiveTo,
    this.createdAt,
    this.updatedAt,
  });

  static const List<String> weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  String get dayName =>
      (dayOfWeek >= 1 && dayOfWeek <= 7) ? weekdayNames[dayOfWeek - 1] : '';

  static String formatMinutes(int minutes) {
    final tod = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    final h = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
    final m = tod.minute.toString().padLeft(2, '0');
    final period = tod.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  String get timeRangeLabel =>
      '${formatMinutes(startMinutes)} - ${formatMinutes(endMinutes)}';

  String get displayLabel => isBreak
      ? 'Break'
      : '$className${section.isNotEmpty ? '-$section' : ''}'
          '${subject.isNotEmpty ? ' ($subject)' : ''}';

  Map<String, dynamic> toMap() {
    return {
      'academy_id': academyId,
      'is_break': isBreak,
      'class_id': classId,
      'class_name': className,
      'section': section,
      'subject': subject,
      'teacher_id': teacherId,
      'teacher_name': teacherName,
      'day_of_week': dayOfWeek,
      'start_minutes': startMinutes,
      'end_minutes': endMinutes,
      'room': room,
      'semester': semester,
      'effective_from': effectiveFrom.toUtc().toIso8601String(),
      'effective_to': effectiveTo?.toUtc().toIso8601String(),
      'created_at': createdAt != null
          ? createdAt!.toUtc().toIso8601String()
          : DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static DateTime _parseDate(dynamic val, [DateTime? fallback]) {
    if (val == null) return fallback ?? DateTime.now();
    if (val is DateTime) return val;
    if (val is String) {
      final parsed = DateTime.tryParse(val);
      if (parsed != null) return parsed;
    }
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    return fallback ?? DateTime.now();
  }

  factory TimetableSlot.fromMap(String id, Map<String, dynamic> map) {
    final rawEffFrom = map['effective_from'] ?? map['effectiveFrom'];
    final rawEffTo = map['effective_to'] ?? map['effectiveTo'];
    final rawCreatedAt = map['created_at'] ?? map['createdAt'];
    final rawUpdatedAt = map['updated_at'] ?? map['updatedAt'];

    return TimetableSlot(
      id: id.isNotEmpty ? id : (map['id'] ?? '').toString(),
      academyId: (map['academy_id'] ?? map['academyId'] ?? '').toString(),
      isBreak: map['is_break'] ?? map['isBreak'] ?? false,
      classId: (map['class_id'] ?? map['classId'] ?? '').toString(),
      className: (map['class_name'] ?? map['className'] ?? '').toString(),
      section: (map['section'] ?? '').toString(),
      subject: (map['subject'] ?? '').toString(),
      teacherId: (map['teacher_id'] ?? map['teacherId'] ?? '').toString(),
      teacherName: (map['teacher_name'] ?? map['teacherName'] ?? '').toString(),
      dayOfWeek:
          (map['day_of_week'] ?? map['dayOfWeek'] ?? DateTime.monday) as int,
      startMinutes: (map['start_minutes'] ?? map['startMinutes'] ?? 0) as int,
      endMinutes: (map['end_minutes'] ?? map['endMinutes'] ?? 0) as int,
      room: (map['room'] ?? '').toString(),
      semester: (map['semester'] ?? '').toString(),
      effectiveFrom: _parseDate(rawEffFrom),
      effectiveTo: rawEffTo != null ? _parseDate(rawEffTo) : null,
      createdAt: rawCreatedAt != null ? _parseDate(rawCreatedAt) : null,
      updatedAt: rawUpdatedAt != null ? _parseDate(rawUpdatedAt) : null,
    );
  }
}
