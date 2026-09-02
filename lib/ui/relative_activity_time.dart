/// Produces the deliberately compact relative timestamp used beside DM
/// previews. Calendar-sized months and years keep the label stable and avoid
/// implying precision that the abbreviated navigation row cannot display.
String compactActivityAge(DateTime? timestamp, {DateTime? now}) {
  if (timestamp == null) return '';
  final elapsed = (now ?? DateTime.now()).difference(timestamp.toLocal());
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d';
  if (elapsed.inDays < 30) return '${elapsed.inDays ~/ 7}w';
  if (elapsed.inDays < 365) return '${elapsed.inDays ~/ 30}M';
  return '${elapsed.inDays ~/ 365}y';
}
