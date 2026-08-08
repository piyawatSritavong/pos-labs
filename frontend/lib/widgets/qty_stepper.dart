import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A quantity control that can be stepped **and** typed into.
///
/// The − / + buttons stay for small adjustments, but the number between them is
/// a real text field: reaching 250 by tapping + 250 times is not a thing anyone
/// should have to do.
///
/// While the field has focus the text is left alone — clearing it to retype is
/// normal and must not be fought by a clamp on every keystroke. The value is
/// committed when the user submits or moves away, and only then is it clamped
/// to [min]/[max] and echoed back.
class QtyStepper extends StatefulWidget {
  const QtyStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
    this.enabled = true,
    this.fieldWidth = 56,
    this.iconSize,
    this.compact = false,
    this.onDecrementBelowMin,
    this.decrementTooltip = 'ลดจำนวน',
    this.incrementTooltip = 'เพิ่มจำนวน',
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;

  /// Upper bound, inclusive. Null means unbounded.
  final int? max;

  final bool enabled;
  final double fieldWidth;
  final double? iconSize;

  /// Tightens paddings for use inside a dense table row.
  final bool compact;

  /// Called instead of clamping when − is pressed at [min] — lets a caller
  /// drop the whole line rather than sit at 1. Typed input still clamps, so
  /// the destructive path stays behind a deliberate button press.
  final VoidCallback? onDecrementBelowMin;

  final String decrementTooltip;
  final String incrementTooltip;

  @override
  State<QtyStepper> createState() => _QtyStepperState();
}

class _QtyStepperState extends State<QtyStepper> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        // Selecting everything makes overtyping the common case one gesture.
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      } else {
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(QtyStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Mirror changes that came from elsewhere (the buttons, a reset), but never
    // while the user is mid-edit.
    if (widget.value != oldWidget.value && !_focusNode.hasFocus) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  int _clamp(int value) {
    if (value < widget.min) return widget.min;
    final max = widget.max;
    if (max != null && value > max) return max;
    return value;
  }

  /// Applies whatever is in the field. An unparseable or empty field falls back
  /// to the current value, so a stray tap never silently zeroes a line.
  void _commit() {
    final typed = int.tryParse(_controller.text.trim());
    final next = _clamp(typed ?? widget.value);
    if (_controller.text != '$next') {
      _controller.text = '$next';
    }
    if (next != widget.value) {
      widget.onChanged(next);
    }
  }

  void _step(int delta) {
    final target = widget.value + delta;
    if (delta < 0 && target < widget.min) {
      widget.onDecrementBelowMin?.call();
      return;
    }
    final next = _clamp(target);
    if (next == widget.value) return;
    _controller.text = '$next';
    widget.onChanged(next);
  }

  bool get _canDecrement =>
      widget.enabled &&
      (widget.value > widget.min || widget.onDecrementBelowMin != null);

  bool get _canIncrement =>
      widget.enabled && (widget.max == null || widget.value < widget.max!);

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.iconSize ?? (widget.compact ? 20 : 24);
    final constraints = widget.compact
        ? const BoxConstraints.tightFor(width: 32, height: 32)
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _canDecrement ? () => _step(-1) : null,
          icon: const Icon(Icons.remove),
          iconSize: iconSize,
          constraints: constraints,
          padding: widget.compact ? EdgeInsets.zero : null,
          visualDensity: widget.compact ? VisualDensity.compact : null,
          tooltip: widget.decrementTooltip,
        ),
        SizedBox(
          width: widget.fieldWidth,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: widget.enabled,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _commit(),
            // Tapping elsewhere in the dialog is the usual way out of the
            // field on desktop; treat it like leaving it.
            onTapOutside: (_) {
              if (_focusNode.hasFocus) _focusNode.unfocus();
            },
          ),
        ),
        IconButton(
          onPressed: _canIncrement ? () => _step(1) : null,
          icon: const Icon(Icons.add),
          iconSize: iconSize,
          constraints: constraints,
          padding: widget.compact ? EdgeInsets.zero : null,
          visualDensity: widget.compact ? VisualDensity.compact : null,
          tooltip: widget.incrementTooltip,
        ),
      ],
    );
  }
}
