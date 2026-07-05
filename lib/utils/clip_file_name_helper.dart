class ClipFileNameHelper {
  static String buildClipFileName({
    required String title,
    required int startSeconds,
    required int endSeconds,
  }) {
    final safeTitle = _sanitizeTitle(title);
    final start = _formatSeconds(startSeconds);
    final end = _formatSeconds(endSeconds);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    return '${safeTitle}_${start}_to_${end}_$timestamp.mp4';
  }

  static String _sanitizeTitle(String title) {
    final cleaned = title
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    if (cleaned.isEmpty) {
      return 'Clip';
    }

    return cleaned;
  }

  static String _formatSeconds(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');

    return '${mm}_${ss}';
  }
}