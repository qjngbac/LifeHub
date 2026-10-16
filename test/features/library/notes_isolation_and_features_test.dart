import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/course/data/academic_repository.dart';
import 'package:lifehub/features/course/data/course_repository.dart';
import 'package:lifehub/features/inbox/data/inbox_repository.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';

void main() {
  late AppDatabase database;
  late SavedItemRepository savedRepo;
  late CourseRepository courseRepo;
  late AcademicRepository academicRepo;
  late InboxRepository inboxRepo;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    savedRepo = SavedItemRepository(database);
    courseRepo = CourseRepository(database);
    academicRepo = AcademicRepository(database);
    inboxRepo = InboxRepository(database);
  });

  tearDown(() => database.close());

  test('listNotes strictly isolates personal notes from Course and Inbox items', () async {
    // 1. Create a pure personal note
    final personalNote = await savedRepo.create(
      const SavedItemDraft(
        title: '我的生活便签',
        content: '周末去公园骑车',
      ),
    );

    // 2. Create a semester & course, and add course material
    final semester = await courseRepo.createSemester(
      SemesterDraft(
        name: '2026秋季学期',
        start: DateTime(2026, 9, 1),
        end: DateTime(2027, 1, 15),
        totalWeeks: 20,
      ),
    );
    final course = await courseRepo.createCourse(
      CourseDraft(semesterId: semester.id, name: '高等数学'),
    );
    await academicRepo.createMaterial(
      courseId: course.id,
      title: '高数期末复习课件',
      content: '微积分重点章节与公式汇总',
    );

    // 3. Create an inbox entry and convert to saved item
    final inboxItem = await inboxRepo.capture('发现一个很棒的设计灵感链接 https://example.com');
    await inboxRepo.convertToSavedItem(inboxItem.id);

    // 4. Verify listNotes only returns the pure personal note!
    final notes = await savedRepo.listNotes();
    expect(notes.length, 1);
    expect(notes.first.id, personalNote.id);
    expect(notes.first.title, '我的生活便签');
    expect(notes.any((n) => n.title.contains('高数')), isFalse);
    expect(notes.any((n) => n.title.contains('灵感')), isFalse);
  });

  test('Note pinning and color customization work seamlessly', () async {
    final note1 = await savedRepo.create(
      const SavedItemDraft(title: '普通便签1', content: '内容1'),
    );
    final note2 = await savedRepo.create(
      const SavedItemDraft(title: '重要置顶便签', content: '置顶内容'),
    );

    // Pin note2 and give it a yellow color
    await savedRepo.togglePin(note2.id);
    await savedRepo.updateNoteColor(note2.id, '#FFF9C4');

    final notes = await savedRepo.listNotes();
    expect(notes.length, 2);
    // Pinned note must be first
    expect(notes.first.id, note2.id);
    expect(notes.last.id, note1.id);

    final meta = NoteMetadata.fromSourceUri(notes.first.sourceUri);
    expect(meta.isPinned, isTrue);
    expect(meta.colorHex, '#FFF9C4');
  });

  test('Deleting course cleanly cascades and removes linked course materials', () async {
    final semester = await courseRepo.createSemester(
      SemesterDraft(
        name: '2026春季学期',
        start: DateTime(2026, 3, 1),
        end: DateTime(2026, 7, 1),
        totalWeeks: 18,
      ),
    );
    final course = await courseRepo.createCourse(
      CourseDraft(semesterId: semester.id, name: '计算机组成原理'),
    );
    final material = await academicRepo.createMaterial(
      courseId: course.id,
      title: '计组课后实验指南',
      content: 'CPU设计指令集实验',
    );

    // Verify material exists
    final beforeDelete = await savedRepo.get(material.id);
    expect(beforeDelete.deletedAt, isNull);

    // Delete course
    await courseRepo.deleteCourse(course.id);

    // Verify material is now soft-deleted!
    final afterDelete = await savedRepo.get(material.id);
    expect(afterDelete.deletedAt, isNotNull);
  });

  test('NoteMetadata correctly encodes and decodes fontSize, pin and color', () {
    const meta = NoteMetadata(
      isPinned: true,
      colorHex: '#E8F5E9',
      fontSize: 19.5,
    );
    final jsonUri = meta.toSourceUri();
    final decoded = NoteMetadata.fromSourceUri(jsonUri);

    expect(decoded.isPinned, isTrue);
    expect(decoded.colorHex, '#E8F5E9');
    expect(decoded.fontSize, 19.5);

    // Test copyWith
    final updated = decoded.copyWith(fontSize: 22.5, clearColor: true);
    expect(updated.fontSize, 22.5);
    expect(updated.colorHex, isNull);
    expect(updated.isPinned, isTrue);

    // Null and empty handling
    expect(NoteMetadata.fromSourceUri(null).isPinned, isFalse);
    expect(NoteMetadata.fromSourceUri('').fontSize, isNull);
  });
}
