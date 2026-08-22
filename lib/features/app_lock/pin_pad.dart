import 'package:flutter/material.dart';

class PinPad extends StatelessWidget {
  const PinPad({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  void _append(String digit) {
    if (enabled && value.length < 6) {
      onChanged('$value$digit');
    }
  }

  void _remove() {
    if (enabled && value.isNotEmpty) {
      onChanged(value.substring(0, value.length - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = <Widget>[
      for (var digit = 1; digit <= 9; digit++)
        _PinKey(
            label: '$digit', onTap: () => _append('$digit'), enabled: enabled),
      const SizedBox.shrink(),
      _PinKey(label: '0', onTap: () => _append('0'), enabled: enabled),
      _PinKey(
          icon: Icons.backspace_outlined,
          label: '删除',
          onTap: _remove,
          enabled: enabled),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '已输入 ${value.length} 位数字',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              6,
              (index) => Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index < value.length
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  border:
                      Border.all(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 36),
        SizedBox(
          width: 300,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.7,
            physics: const NeverScrollableScrollPhysics(),
            children: keys,
          ),
        ),
      ],
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({
    this.label,
    this.icon,
    required this.onTap,
    required this.enabled,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (label == null && icon == null) {
      return const SizedBox.shrink();
    }
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Center(
          child: icon == null
              ? Text(label!, style: Theme.of(context).textTheme.headlineSmall)
              : Icon(icon, size: 22),
        ),
      ),
    );
  }
}
