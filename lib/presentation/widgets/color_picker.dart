import 'package:flutter/material.dart';

/// Palette swatches plus a "custom" option with hue/saturation/brightness
/// sliders. No extra packages needed.
class ColorPickerField extends StatelessWidget {
  const ColorPickerField({super.key, required this.colors, required this.selected, required this.onChanged});

  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final isCustom = !colors.any((c) => c.toARGB32() == selected.toARGB32());
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final c in colors) _Swatch(color: c, selected: c.toARGB32() == selected.toARGB32(), onTap: () => onChanged(c)),
        Semantics(
          button: true,
          label: 'Custom color',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () async {
              final picked = await showCustomColorDialog(context, selected);
              if (picked != null) onChanged(picked);
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCustom ? selected : null,
                gradient: isCustom
                    ? null
                    : const SweepGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red]),
                border: isCustom ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3) : null,
              ),
              child: const Icon(Icons.colorize_rounded, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: 'Color',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: selected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3) : null,
            ),
            child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
          ),
        ),
      );
}

Future<Color?> showCustomColorDialog(BuildContext context, Color initial) {
  var hsv = HSVColor.fromColor(initial);
  return showDialog<Color>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Custom color'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(color: hsv.toColor(), borderRadius: BorderRadius.circular(14)),
            ),
            const SizedBox(height: 16),
            _slider('Hue', hsv.hue, 0, 360, (v) => setState(() => hsv = hsv.withHue(v))),
            _slider('Saturation', hsv.saturation, 0, 1, (v) => setState(() => hsv = hsv.withSaturation(v))),
            _slider('Brightness', hsv.value, 0.2, 1, (v) => setState(() => hsv = hsv.withValue(v))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, hsv.toColor()), child: const Text('Use color')),
        ],
      ),
    ),
  );
}

Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged) => Row(
      children: [
        SizedBox(width: 84, child: Text(label)),
        Expanded(
          child: Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: onChanged, label: label),
        ),
      ],
    );
