import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/course/domain/course_grade_rules.dart';

void main() {
  test('weighted summary is available only when weights total one', () {
    expect(
      CourseGradeRules.weightedSummary(const [
        CourseGradeValue(score: 80, maximum: 100, weight: .4),
        CourseGradeValue(score: 90, maximum: 100, weight: .6),
      ]),
      86,
    );
    expect(
      CourseGradeRules.weightedSummary(const [
        CourseGradeValue(score: 80, maximum: 100, weight: .4),
      ]),
      isNull,
    );
  });

  test('invalid scores and weights are rejected', () {
    expect(
      () => CourseGradeRules.validate(score: 101, maximum: 100),
      throwsRangeError,
    );
    expect(
      () => CourseGradeRules.validate(score: 80, maximum: 100, weight: 1.1),
      throwsRangeError,
    );
  });
}
