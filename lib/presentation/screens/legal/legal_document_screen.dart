import 'package:material_ui/material_ui.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final lines = body.trim().split('\n');
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            for (final line in lines)
              if (line.trim().isEmpty)
                const SizedBox(height: 12)
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    style: RegExp(r'^\d+[a-z]?\. ').hasMatch(line) || line == lines.first
                        ? text.titleMedium
                        : text.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
