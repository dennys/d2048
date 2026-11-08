import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:g2048/main.dart';

int _tileCount(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .where((w) => int.tryParse(w.data ?? '') != null)
    .length;

// tester.drag stamps every event at t=0, so velocity is always 0;
// pass explicit timestamps to get a real fling velocity.
Future _swipe(WidgetTester tester, Offset offset) async {
  final center = tester.getCenter(find.byType(AspectRatio));
  final gesture = await tester.startGesture(center);
  for (var i = 1; i <= 5; i++) {
    await gesture.moveTo(
      center + offset * (i / 5),
      timeStamp: Duration(milliseconds: 16 * i),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up(timeStamp: const Duration(milliseconds: 96));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('moves add tiles, undo rolls back to the start', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const Game2048App());
    await tester.pumpAndSettle();
    expect(_tileCount(tester), 2);

    for (final offset in const [
      Offset(0, -120),
      Offset(-120, 0),
      Offset(0, 120),
      Offset(120, 0),
    ]) {
      await _swipe(tester, offset);
    }
    expect(_tileCount(tester), greaterThan(2));

    for (var i = 0; i < 20 && _tileCount(tester) > 2; i++) {
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
    }
    expect(_tileCount(tester), 2);
  });
}
