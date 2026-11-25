import 'package:flutter/material.dart';

const mint = Color(0xffb5e6c8),
    ink = Color(0xff101b19),
    amber = Color(0xffedc38a);
void toast(BuildContext context, String text) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }
}

Future<void> guarded(
  BuildContext context,
  Future<dynamic> Function() action,
) async {
  try {
    final result = await action();
    if (context.mounted && result is String && result.isNotEmpty) {
      toast(context, result);
    }
  } catch (e) {
    if (context.mounted) {
      toast(
        context,
        e.toString().replaceFirst(
          RegExp(r'^(FormatException|Bad state|Unsupported operation):\s*'),
          '',
        ),
      );
    }
  }
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.gradient,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Gradient? gradient;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
      gradient: gradient,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant
            .withValues(alpha: .55),
      ),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class Section extends StatelessWidget {
  const Section(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.warning = false});
  final String text;
  final bool warning;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: warning
          ? (Theme.of(context).brightness == Brightness.dark
                ? amber.withValues(alpha: .12)
                : const Color(0xffffefd9))
          : Theme.of(context).colorScheme.primary.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: warning
            ? (Theme.of(context).brightness == Brightness.dark
                  ? amber
                  : const Color(0xff78501d))
            : Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(
    this.title,
    this.body, {
    super.key,
    this.icon = Icons.folder_open_rounded,
    this.action,
  });
  final String title, body;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(body, textAlign: TextAlign.center),
        if (action != null)
          Padding(padding: const EdgeInsets.only(top: 18), child: action!),
      ],
    ),
  );
}
