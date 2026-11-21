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

/// Baut eine [Card] mit mehreren [ListTile]-Einträgen, bei denen der
/// Ink-Ripple exakt an die abgerundeten Ecken angepasst ist:
///
///  • erstes Element  → oben abgerundet
///  • letztes Element → unten abgerundet
///  • einziges Element → rundum abgerundet
///  • mittlere Elemente → eckig (liegen nie an einer Kartenecke)
///
/// [items] ist eine Liste von [GroupedCardItem]-Objekten.
/// Optionaler [elevation] und [margin] werden direkt an die [Card] weitergegeben.
///
/// Beispiel:
/// ```dart
/// GroupedCard(
///   items: [
///     GroupedCardItem(
///       leading: const Icon(Icons.dark_mode),
///       title: const Text('Dark Mode'),
///       onTap: () { … },
///     ),
///     GroupedCardItem(
///       leading: const Icon(Icons.language),
///       title: const Text('Sprache'),
///       onTap: () { … },
///       dividerAbove: true,  // Trennlinie vor diesem Eintrag (Standard: true)
///     ),
///   ],
/// )
/// ```
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
      // clipBehavior ist im CardTheme (main.dart) bereits gesetzt,
      // hier nochmals explizit für den Fall, dass jemand den Theme überschreibt.
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
    // Welche Ecken soll der Ripple abrunden?
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
      // SwitchListTile hat kein eigenes borderRadius-Argument.
      // Wir wrappen es in ein InkWell mit der richtigen Form.
      // Das SwitchListTile selbst wird mit splashColor transparent
      // gemacht, damit kein doppelter Ripple entsteht.
      return item._buildSwitch(radius);
    }

    return item._buildTile(radius);
  }
}

/// Beschreibt einen einzelnen Eintrag in einer [GroupedCard].
class GroupedCardItem {
  // ── Standard ListTile ──────────────────────────────────────────────────
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dividerAbove;

  // ── Switch-Variante ───────────────────────────────────────────────────
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
    return ClipRRect(
      borderRadius: radius,
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