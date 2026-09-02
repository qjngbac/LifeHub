import 'dart:async';

import 'package:drift/drift.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Tests deliberately open separate in-memory databases for round-trip and
  // migration checks. They never share an executor, so Drift's global warning
  // is not actionable in this test process.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await testMain();
}
