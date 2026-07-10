import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/features/match/widgets/hold_button.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 120, height: 60, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('quick tap fires onTap and not onHoldComplete', (tester) async {
    // Arrange
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(_wrap(HoldButton(
      onTap: () => taps++,
      onHoldComplete: () => holds++,
      accentColor: Colors.green,
      child: const Text('+2'),
    )));

    // Act
    await tester.tap(find.text('+2'));
    await tester.pumpAndSettle();

    // Assert
    expect(taps, 1);
    expect(holds, 0);
  });

  testWidgets('holding for 1 second fires onHoldComplete and not onTap',
      (tester) async {
    // Arrange
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(_wrap(HoldButton(
      onTap: () => taps++,
      onHoldComplete: () => holds++,
      accentColor: Colors.green,
      child: const Text('+2'),
    )));

    // Act
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('+2')));
    await tester.pump(); // first ticker frame (t = 0)
    await tester.pump(const Duration(milliseconds: 1100));
    await gesture.up();
    await tester.pumpAndSettle();

    // Assert
    expect(holds, 1);
    expect(taps, 0);
  });

  testWidgets('releasing before 1 second fires onTap only', (tester) async {
    // Arrange
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(_wrap(HoldButton(
      onTap: () => taps++,
      onHoldComplete: () => holds++,
      accentColor: Colors.green,
      child: const Text('+2'),
    )));

    // Act
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('+2')));
    await tester.pump(); // first ticker frame (t = 0)
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();

    // Assert
    expect(taps, 1);
    expect(holds, 0);
  });

  testWidgets('disabled button fires nothing', (tester) async {
    // Arrange
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(_wrap(HoldButton(
      enabled: false,
      onTap: () => taps++,
      onHoldComplete: () => holds++,
      accentColor: Colors.green,
      child: const Text('+2'),
    )));

    // Act
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('+2')));
    await tester.pump(); // first ticker frame (t = 0)
    await tester.pump(const Duration(milliseconds: 1100));
    await gesture.up();
    await tester.pumpAndSettle();

    // Assert
    expect(taps, 0);
    expect(holds, 0);
  });

  testWidgets('hold-only button (no onTap) does nothing on quick release',
      (tester) async {
    // Arrange
    var holds = 0;
    await tester.pumpWidget(_wrap(HoldButton(
      onHoldComplete: () => holds++,
      accentColor: Colors.red,
      child: const Text('Cancelar'),
    )));

    // Act
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    // Assert
    expect(holds, 0);
  });

  testWidgets('hold-only button fires onHoldComplete after 1 second',
      (tester) async {
    // Arrange
    var holds = 0;
    await tester.pumpWidget(_wrap(HoldButton(
      onHoldComplete: () => holds++,
      accentColor: Colors.red,
      child: const Text('Cancelar'),
    )));

    // Act
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Cancelar')));
    await tester.pump(); // first ticker frame (t = 0)
    await tester.pump(const Duration(milliseconds: 1100));
    await gesture.up();
    await tester.pumpAndSettle();

    // Assert
    expect(holds, 1);
  });

  testWidgets('button disabled mid-hold does not fire onHoldComplete',
      (tester) async {
    // Arrange
    var holds = 0;
    Widget build(bool enabled) => _wrap(HoldButton(
          enabled: enabled,
          onHoldComplete: () => holds++,
          accentColor: Colors.red,
          child: const Text('Cancelar'),
        ));
    await tester.pumpWidget(build(true));

    // Act: start holding, then disable before the hold completes
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Cancelar')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(build(false));
    await tester.pump(const Duration(milliseconds: 1100));
    await gesture.up();
    await tester.pumpAndSettle();

    // Assert
    expect(holds, 0);
  });
}
