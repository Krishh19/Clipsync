import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'db.g.dart';

class Transfers extends Table {
  TextColumn get id => text()();
  TextColumn get direction => text()(); // 'in' or 'out'
  TextColumn get kind => text()(); // 'text', 'link', 'image', 'video', 'file'
  TextColumn get label => text()();
  TextColumn get filePath => text().nullable()();
  IntColumn get size => integer()();
  TextColumn get status => text()(); // 'queued', 'sending', 'done', 'failed'
  TextColumn get error => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Transfers])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(transfers, transfers.filePath);
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'clipsync.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
