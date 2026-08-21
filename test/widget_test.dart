// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:projctlitudei/features/training/presentation/training_screen.dart';

void main() {
  testWidgets('training screen loads the current annotation workflow', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: TrainingScreen()));
    await tester.pumpAndSettle();

    expect(find.text('مدرّب الرؤية الذكي'), findsOneWidget);
    expect(find.text('جمع الصور'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('التصنيف والمربع'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Select images'), findsOneWidget);
    expect(find.text('Upload All'), findsOneWidget);
    expect(find.text('Start Training'), findsNothing);
    expect(find.text('Download Model'), findsNothing);
    expect(find.text('فئة مخصصة'), findsOneWidget);
    expect(find.text('إعدادات Roboflow'), findsNothing);
  });
}
