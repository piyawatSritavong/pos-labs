import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/qty_stepper.dart';

/// Hosts the stepper the way a real screen does: the parent owns the value and
/// feeds it back down, so these tests also cover the round trip.
class _Host extends StatefulWidget {
  const _Host({
    required this.initial,
    this.min = 0,
    this.max,
    this.onDecrementBelowMin,
  });

  final int initial;
  final int min;
  final int? max;
  final VoidCallback? onDecrementBelowMin;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            QtyStepper(
              value: value,
              min: widget.min,
              max: widget.max,
              onDecrementBelowMin: widget.onDecrementBelowMin,
              onChanged: (next) => setState(() => value = next),
            ),
            Text('value=$value'),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('typing a quantity replaces it without touching the buttons', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host(initial: 7, min: 1, max: 1850));

    await tester.enterText(find.byType(TextField), '250');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('value=250'), findsOneWidget);
  });

  testWidgets('the − and + buttons still step by one', (tester) async {
    await tester.pumpWidget(const _Host(initial: 7, min: 1, max: 1850));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('value=8'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(find.text('value=7'), findsOneWidget);
  });

  testWidgets('a stepped value shows up in the field', (tester) async {
    await tester.pumpWidget(const _Host(initial: 7, min: 1, max: 1850));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '8');
  });

  testWidgets('a typed value over the maximum is clamped down', (tester) async {
    await tester.pumpWidget(const _Host(initial: 7, min: 1, max: 1850));

    await tester.enterText(find.byType(TextField), '99999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('value=1850'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '1850');
  });

  testWidgets('a typed value under the minimum is clamped up', (tester) async {
    await tester.pumpWidget(const _Host(initial: 7, min: 1, max: 1850));

    await tester.enterText(find.byType(TextField), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('value=1'), findsOneWidget);
  });

  testWidgets('clearing the field falls back to the current quantity', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host(initial: 7, min: 1, max: 1850));

    await tester.enterText(find.byType(TextField), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('value=7'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '7');
  });

  testWidgets('pressing − at the minimum hands off to the caller', (
    tester,
  ) async {
    var removed = false;
    await tester.pumpWidget(
      _Host(
        initial: 1,
        min: 1,
        max: 10,
        onDecrementBelowMin: () => removed = true,
      ),
    );

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();

    expect(removed, isTrue);
    expect(find.text('value=1'), findsOneWidget);
  });

  testWidgets('+ is disabled at the maximum and − at the minimum', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host(initial: 3, min: 3, max: 3));

    final plus = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(IconButton),
      ),
    );
    final minus = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.remove),
        matching: find.byType(IconButton),
      ),
    );
    expect(plus.onPressed, isNull);
    expect(minus.onPressed, isNull);
  });
}
