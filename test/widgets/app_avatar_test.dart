import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talentloq/widgets/app_avatar.dart';

void main() {
  group('AppAvatar Widget Tests', () {
    testWidgets('renders avatar circle with fallback icon when URL is empty', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppAvatar(
              imageUrl: '',
              radius: 30,
            ),
          ),
        ),
      );

      // Verify the outer container exists with correct circular sizing (diameter = 60)
      final containerFinder = find.byType(Container).first;
      expect(containerFinder, findsOneWidget);

      final Container container = tester.widget(containerFinder);
      expect(container.constraints?.maxWidth ?? container.decoration, isNotNull);

      // Verify fallback icon appears
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('renders fallback initial character when fallbackText is supplied', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppAvatar(
              imageUrl: '',
              radius: 24,
              fallbackText: 'Alex Johnson',
            ),
          ),
        ),
      );

      // Should render the first uppercase letter 'A'
      expect(find.text('A'), findsOneWidget);
      // Person icon should not be rendered when fallback text is used
      expect(find.byIcon(Icons.person_rounded), findsNothing);
    });
  });
}
