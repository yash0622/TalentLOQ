import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talentloq/widgets/talentloq_branding_header.dart';

void main() {
  group('TalentloqBrandingHeader Widget Tests', () {
    testWidgets('renders properly with default icon mode in light theme', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: const Scaffold(
            body: TalentloqBrandingHeader(height: 32),
          ),
        ),
      );

      // Verify widget mounts and has Image or fallback Icon
      expect(find.byType(TalentloqBrandingHeader), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('renders properly with default icon mode in dark theme', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: TalentloqBrandingHeader(height: 32),
          ),
        ),
      );

      expect(find.byType(TalentloqBrandingHeader), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('renders in wordmark mode', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: const Scaffold(
            body: TalentloqBrandingHeader(height: 40, showWordmark: true),
          ),
        ),
      );

      expect(find.byType(TalentloqBrandingHeader), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
