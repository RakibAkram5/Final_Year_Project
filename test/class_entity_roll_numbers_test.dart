import 'package:flutter_test/flutter_test.dart';
import 'package:taleemplus_app/data/models/class_entity.dart';

void main() {
  test('ClassEntity parses and round-trips student roll numbers', () {
    final entity = ClassEntity.fromMap('c1', {
      'academy_id': 'a1',
      'class_name': '9th Class',
      'student_ids': ['s1', 's2'],
      'student_names': {'s1': 'Ali', 's2': 'Sana'},
      'student_roll_numbers': {'s1': '9B-10', 's2': '9B-02'},
      'created_at': '2026-11-01T00:00:00Z',
    });
    expect(entity.studentRollNumbers, {'s1': '9B-10', 's2': '9B-02'});
    final again = ClassEntity.fromMap('c1', entity.toMap());
    expect(again.studentRollNumbers['s2'], '9B-02');
  });

  test('ClassEntity tolerates a payload without roll numbers', () {
    final entity = ClassEntity.fromMap('c1', {'class_name': 'X'});
    expect(entity.studentRollNumbers, isEmpty);
  });
}
