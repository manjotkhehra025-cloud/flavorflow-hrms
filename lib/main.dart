import 'package:flutter/material.dart';

import 'app.dart';
import 'app_providers.dart';
import 'repositories/repository_factory.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Swap mock data for a real backend inside buildRepositories().
  final repos = buildRepositories();

  runApp(AppProviders(repositories: repos, child: const IhrmsApp()));
}
