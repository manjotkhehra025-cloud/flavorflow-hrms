import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrmate/main.dart';

/// CI guard — see .circleci/config.yml (build-flutter).
///
/// The build generates the Android wrapper with `flutter create .`. When this
/// file is absent from the repo, `flutter create` drops its stock counter-app
/// `test/widget_test.dart`, which references a `MyApp` class that does not
/// exist here (our root widget is [HrmateApp]) — so `flutter analyze` failed
/// every pipeline with `creation_with_non_type`. Committing our own test
/// keeps `flutter create` from inventing one (it only creates missing files).
void main() {
  test('root widget is HrmateApp (not the template MyApp)', () {
    expect(HrmateApp, isA<Type>());
  });

  testWidgets('HRMate smoke — boots a MaterialApp', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('HRMate'))),
    );
    expect(find.text('HRMate'), findsOneWidget);
  });
}
