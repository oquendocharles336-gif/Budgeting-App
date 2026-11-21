import 'package:flutter/material.dart';

class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, this.max = 6});
  final int length;
  final int max;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$length digits entered',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < max; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < length ? scheme.primary : Colors.transparent,
                border: Border.all(color: i < length ? scheme.primary : scheme.outline, width: 2),
              ),
            ),
        ],
      ),
    );
  }
}

/// Large number pad. [extraButton] goes bottom-left (e.g. fingerprint).
class PinPad extends StatelessWidget {
  const PinPad({super.key, required this.onDigit, required this.onBackspace, this.extraButton});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Widget? extraButton;

  @override
  Widget build(BuildContext context) {
    Widget key(String d) => _Key(label: d, onTap: () => onDigit(d));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final d in row) key(d)]),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 88, height: 72, child: Center(child: extraButton)),
            key('0'),
            SizedBox(
              width: 88,
              height: 72,
              child: IconButton(
                tooltip: 'Delete digit',
                iconSize: 28,
                onPressed: onBackspace,
                icon: const Icon(Icons.backspace_outlined),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 72,
            height: 56,
            child: Center(
              child: Text(label, style: Theme.of(context).textTheme.headlineSmall),
            ),
          ),
        ),
      ),
    );
  }
}
