import 'package:get_it/get_it.dart';
import '../../data/local/database_helper.dart';
import '../../services/sync/sync_service.dart';

final getIt = GetIt.instance;

void setupDependencies() {
  getIt.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper());
  getIt.registerLazySingleton<SyncService>(() => SyncService());
}
