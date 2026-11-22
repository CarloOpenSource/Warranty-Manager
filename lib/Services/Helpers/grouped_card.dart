import 'package:flutter/material.dart';

/// Radius der Card-Ecken – muss mit dem CardTheme in main.dart übereinstimmen.
const double _kCardRadius = 12.0;

const _kTopRadius = BorderRadius.only(
  topLeft: Radius.circular(_kCardRadius),
  topRight: Radius.circular(_kCardRadius),
);
const _kBottomRadius = BorderRadius.only(
  bottomLeft: Radius.circular(_kCardRadius),
  bottomRight: Radius.circular(_kCardRadius),
);
const _kAllRadius = BorderRadius.all(Radius.circular(_kCardRadius));

/// Baut eine [Card] mit mehreren Einträgen, bei denen der Ink-Ripple exakt
/// an die abgerundeten Ecken angepasst ist:
///
///  • erstes Element   → oben abgerundet
///  • letztes Element  → unten abgerundet
///  • einziges Element → rundum abgerundet
///  • mittlere Elemente → eckig (liegen nie an einer Kartenecke)
class GroupedCard extends StatelessWidget {
  final List<GroupedCardItem> items;
  final double elevation;
  final EdgeInsetsGeometry? margin;

  const GroupedCard({
    super.key,
    required this.items,
    this.elevation = 2,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    assert(items.isNotEmpty, 'GroupedCard braucht mindestens einen Eintrag.');

    return Card(
      elevation: elevation,
      margin: margin,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(_kCardRadius)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0 && items[i].dividerAbove) const Divider(height: 1),
            _buildTile(context, items[i], i, items.length),
          ],
        ],
      ),
    );
  }

  Widget _buildTile(
      BuildContext context, GroupedCardItem item, int index, int total) {
    final BorderRadius radius;
    if (total == 1) {
      radius = _kAllRadius;
    } else if (index == 0) {
      radius = _kTopRadius;
    } else if (index == total - 1) {
      radius = _kBottomRadius;
    } else {
      radius = BorderRadius.zero;
    }

    if (item.isSwitchTile) {
      return item._buildSwitch(radius);
    }
    return item._buildTile(radius);
  }
}

/// Beschreibt einen einzelnen Eintrag in einer [GroupedCard].
class GroupedCardItem {
  // ── Standard ListTile ────────────────────────────────────────────────
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dividerAbove;

  // ── Switch-Variante ──────────────────────────────────────────────────
  final bool isSwitchTile;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitchChanged;
  final Widget? switchSecondary;

  const GroupedCardItem({
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.dividerAbove = true,
  })  : isSwitchTile = false,
        switchValue = null,
        onSwitchChanged = null,
        switchSecondary = null;

  const GroupedCardItem.switchTile({
    this.leading,
    this.switchSecondary,
    required this.title,
    this.subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    this.dividerAbove = true,
  })  : isSwitchTile = true,
        switchValue = value,
        onSwitchChanged = onChanged,
        trailing = null,
        onTap = null;

  Widget _buildTile(BorderRadius radius) {
    return Material(
      type: MaterialType.transparency,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: ListTile(
          leading: leading,
          title: title,
          subtitle: subtitle,
          trailing: trailing,
        ),
      ),
    );
  }

  Widget _buildSwitch(BorderRadius radius) {
    // Material mit clipBehavior ist die einzig zuverlässige Methode,
    // den SwitchListTile-Ripple an den Ecken abzuschneiden.
    // ClipRRect allein reicht nicht, weil der Ink-Layer von Flutter
    // ÜBER dem Clip gerendert wird.
    return Material(
      type: MaterialType.transparency,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        secondary: switchSecondary ?? leading,
        title: title!,
        subtitle: subtitle,
        value: switchValue!,
        onChanged: onSwitchChanged,
      ),
    );
  }
}