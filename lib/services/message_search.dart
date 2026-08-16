/// Applies deterministic client-side relevance filtering to Matrix search
/// results. Synapse may include contextual events around an actual hit; every
/// query term must occur in either the message body or sender for Deltiecord to
/// present the event as a result.
bool matchesMessageSearch({
  required String body,
  required String sender,
  required String query,
}) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList(growable: false);
  if (terms.isEmpty) return false;
  final searchable = '${sender.toLowerCase()}\n${body.toLowerCase()}';
  return terms.every(searchable.contains);
}
