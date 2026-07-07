import 'package:flutter/material.dart';

/// Teclado numérico propio con botones grandes para captura táctil rápida
/// en tablet/mostrador. No depende del teclado del sistema (evita que el
/// layout salte) y admite decimales.
///
/// Opera sobre un texto plano: el widget padre mantiene el estado y decide
/// cómo interpretarlo (cantidad, precio…). La tecla ⌫ borra un dígito;
/// `.` agrega un único punto decimal. La acción "limpiar" la ofrece el
/// padre junto al display.
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowDecimal = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool allowDecimal;

  void _tap(String key) {
    switch (key) {
      case '⌫':
        if (value.isNotEmpty) onChanged(value.substring(0, value.length - 1));
      case '.':
        if (allowDecimal && !value.contains('.')) {
          onChanged(value.isEmpty ? '0.' : '$value.');
        }
      case '':
        break; // tecla inactiva (sin decimales)
      default:
        // Evita ceros a la izquierda tipo "007".
        onChanged(value == '0' ? key : '$value$key');
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = <String>[
      '7', '8', '9',
      '4', '5', '6',
      '1', '2', '3',
      allowDecimal ? '.' : '', '0', '⌫',
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.0,
      children: [
        for (final key in keys)
          key.isEmpty
              ? const SizedBox.shrink()
              : _KeypadButton(label: key, onTap: () => _tap(key)),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBackspace = label == '⌫';

    return Material(
      color:
          isBackspace ? scheme.surfaceContainerHighest : scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isBackspace
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                ),
          ),
        ),
      ),
    );
  }
}
