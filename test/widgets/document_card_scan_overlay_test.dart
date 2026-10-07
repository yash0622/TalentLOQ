import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talentloq/widgets/document_card_scan_overlay.dart';

void main() {
  group('DocumentCardScanOverlay Widget Tests', () {
    testWidgets('renders processing status with stage text and spinner', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 120,
              child: DocumentCardScanOverlay(
                status: DocumentScanStatus.processing,
                stageText: 'Parsing document…',
                isDark: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Parsing document…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders success state with check icon and message', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 120,
              child: DocumentCardScanOverlay(
                status: DocumentScanStatus.success,
                stageText: 'Verified',
                isDark: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Verified successfully!'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('renders error state with retry action', (WidgetTester tester) async {
      bool retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 120,
              child: DocumentCardScanOverlay(
                status: DocumentScanStatus.error,
                stageText: 'Error',
                errorMessage: 'Invalid format',
                onRetry: () => retried = true,
                isDark: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Invalid format'), findsOneWidget);
      expect(find.text('Retry Scan'), findsOneWidget);

      await tester.tap(find.text('Retry Scan'));
      expect(retried, isTrue);
    });
  });
}
