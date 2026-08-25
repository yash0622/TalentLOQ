import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talentloq/main.dart';

void main() {
  testWidgets('TalentLOQ app loads home screen test', (WidgetTester tester) async {
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception is NetworkImageLoadException) {
        return; // Ignore network image loading in headless widget tests
      }
      FlutterError.presentError(details);
    };

    await tester.pumpWidget(const TalentLOQApp());
    expect(find.text('TalentLOQ'), findsWidgets);
  });
}
