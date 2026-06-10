/// Tiempo relativo en español para listados ("hace 5 min", "ayer").
String timeAgo(DateTime date, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(date.toLocal());

  if (diff.inSeconds < 60) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) {
    return diff.inHours == 1 ? 'hace 1 hora' : 'hace ${diff.inHours} horas';
  }
  if (diff.inDays == 1) return 'ayer';
  if (diff.inDays < 30) return 'hace ${diff.inDays} días';

  final local = date.toLocal();
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  return '$dd/$mm/${local.year}';
}
