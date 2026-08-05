import 'package:flutter/material.dart';
import 'app/app.dart';
import 'data/repository.dart';
import 'data/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsStore.i.load();
  await Repo.i.init();
  runApp(const DieciApp());
}
