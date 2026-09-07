import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:talentloq/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TalentLOQ app loads home screen test', (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const TalentLOQApp());
    await tester.pump();
    expect(find.byType(TalentLOQApp), findsOneWidget);
  });
}
