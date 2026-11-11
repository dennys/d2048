import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d2048/game_storage.dart';
import 'package:d2048/main.dart';
import 'package:d2048/settings_model.dart';

void main() {
  testWidgets('telegram fields persist on Test and blank channel is rejected', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await GameStorage(prefs).addPlayer('Amy');
    final settings = await SettingsModel.load(prefs);
    await tester.pumpWidget(Game2048App(settings: settings, prefs: prefs, random: Random(1)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Invalid channel name'), findsOneWidget);
    expect(settings.telegramChannel, isEmpty);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '@repro_chan');
    await tester.enterText(fields.at(1), 'tok123');
    await tester.pump();
    await tester.ensureVisible(find.text('Test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();

    expect(settings.telegramChannel, 'repro_chan');
    expect(settings.telegramToken, 'tok123');
    expect(prefs.getString('telegram_channel'), 'repro_chan');
    expect(prefs.getString('telegram_token'), 'tok123');
  });
}
