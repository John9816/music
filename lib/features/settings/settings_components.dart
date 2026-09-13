import 'package:flutter/material.dart';

import '../../widgets/glass.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: TypeScale.bold,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: glassHairline(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: Divider(height: 1, color: glassHairline(context)),
              ),
          ],
        ],
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.onToggle,
    this.toggleValue,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;
  final bool? toggleValue;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentToggleValue = toggleValue ??
        switch (trailing) {
          SettingsSwitch(value: final value) => value,
          Switch(value: final value) => value,
          _ => null,
        };
    final isToggle = onToggle != null && currentToggleValue != null;
    final effectiveOnTap =
        isToggle ? () => onToggle!(!currentToggleValue) : onTap;

    final row = GPressScale(
      onTap: effectiveOnTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 62),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: LayoutBuilder(builder: (context, constraints) {
            final stackValue = value != null &&
                (constraints.maxWidth < 430 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20);
            final valueText = value == null
                ? null
                : Text(
                    value!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: TypeScale.medium,
                      color: scheme.onSurfaceVariant,
                    ),
                  );
            return Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Icon(
                    icon,
                    size: 19,
                    color: destructive ? scheme.error : scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: TypeScale.semibold,
                          color: destructive ? scheme.error : scheme.onSurface,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (stackValue) ...[
                        const SizedBox(height: 5),
                        valueText!,
                      ],
                    ],
                  ),
                ),
                if (valueText != null && !stackValue) ...[
                  const SizedBox(width: 12),
                  Flexible(child: valueText),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  ExcludeFocus(excluding: isToggle, child: trailing!),
                ] else if (onTap != null) ...[
                  const SizedBox(width: 7),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 19,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ],
            );
          }),
        ),
      ),
    );
    if (!isToggle) return row;
    return Semantics(
      label: title,
      hint: subtitle,
      toggled: currentToggleValue,
      enabled: effectiveOnTap != null,
      onTap: effectiveOnTap,
      child: ExcludeSemantics(child: row),
    );
  }
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeTrackColor: Theme.of(context).colorScheme.primary,
    );
  }
}

Future<T?> showSettingsPicker<T>(
  BuildContext context, {
  required String title,
  required T current,
  required List<({T value, String label, String? detail})> options,
}) {
  final isDesktop = MediaQuery.sizeOf(context).width >= GBreakpoints.sidebar;

  if (isDesktop) {
    return showDialog<T>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options)
                GListTile(
                  selected: option.value == current,
                  title: Text(option.label),
                  subtitle: option.detail != null ? Text(option.detail!) : null,
                  trailing: option.value == current
                      ? const Icon(Icons.check_rounded, size: 19)
                      : null,
                  onTap: () => Navigator.of(dialogContext).pop(option.value),
                ),
            ],
          ),
        ),
      ),
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: TypeScale.bold),
              ),
            ),
            for (final option in options)
              GListTile(
                selected: option.value == current,
                title: Text(option.label),
                subtitle: option.detail != null ? Text(option.detail!) : null,
                trailing: option.value == current
                    ? const Icon(Icons.check_rounded, size: 19)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(option.value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
