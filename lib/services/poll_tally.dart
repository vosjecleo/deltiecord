/// Counts Matrix poll responses, which are keyed by voter user ID and contain
/// the answer IDs selected by that voter.
int pollVoteCount(Map<String, Set<String>> responses, String answerId) =>
    responses.values.where((answers) => answers.contains(answerId)).length;

bool pollAnswerSelectedBy(
  Map<String, Set<String>> responses,
  String? userId,
  String answerId,
) => userId != null && (responses[userId]?.contains(answerId) ?? false);
