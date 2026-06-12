import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';

/// Logotipo de la marca. Usa `assets/branding/logo.png` si existe;
/// mientras tanto cae a un monograma dorado con el estilo del logo
/// (caballo "A" de El Alazán), así que la app luce bien desde hoy y
/// mejor cuando se coloque el archivo real.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 32, this.withWordmark = false});

  final double size;
  final bool withWordmark;

  @override
  Widget build(BuildContext context) {
    final mark = ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: Image.asset(
        'assets/branding/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _Monogram(size: size),
      ),
    );

    if (!withWordmark) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppConfig.appName.toUpperCase(),
              style: TextStyle(
                color: AppTheme.brandGold,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                fontSize: size * 0.42,
                height: 1,
              ),
            ),
            Text(
              AppConfig.appTagline.toUpperCase(),
              style: TextStyle(
                color: AppTheme.brandCream,
                letterSpacing: 2,
                fontSize: size * 0.26,
                height: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.brandGreen,
        borderRadius: BorderRadius.circular(size / 4),
        border: Border.all(color: AppTheme.brandGold, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        'A',
        style: TextStyle(
          color: AppTheme.brandGold,
          fontSize: size * 0.55,
          fontWeight: FontWeight.bold,
          fontFamily: 'serif',
          height: 1,
        ),
      ),
    );
  }
}
