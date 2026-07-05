class FaceReactionFrameSignal {
  final int second;
  final int sampleEverySeconds;
  final int faceCount;
  final double smilingScore;
  final double eyeExpressionScore;
  final double headMovementScore;
  final double facePresenceScore;
  final double faceChangeScore;
  final double reactionScore;

  const FaceReactionFrameSignal({
    required this.second,
    required this.sampleEverySeconds,
    required this.faceCount,
    required this.smilingScore,
    required this.eyeExpressionScore,
    required this.headMovementScore,
    required this.facePresenceScore,
    required this.faceChangeScore,
    required this.reactionScore,
  });

  bool get hasFace => faceCount > 0 && facePresenceScore > 0;

  bool get isStrongReaction => reactionScore >= 0.35;

  Map<String, dynamic> toJson() {
    return {
      'second': second,
      'sample_every_seconds': sampleEverySeconds,
      'face_count': faceCount,
      'smiling_score': smilingScore,
      'eye_expression_score': eyeExpressionScore,
      'head_movement_score': headMovementScore,
      'face_presence_score': facePresenceScore,
      'face_change_score': faceChangeScore,
      'reaction_score': reactionScore,
    };
  }

  factory FaceReactionFrameSignal.fromJson(Map<String, dynamic> json) {
    return FaceReactionFrameSignal(
      second: (json['second'] as num?)?.round() ?? 0,
      sampleEverySeconds: (json['sample_every_seconds'] as num?)?.round() ?? 1,
      faceCount: (json['face_count'] as num?)?.round() ?? 0,
      smilingScore: (json['smiling_score'] as num?)?.toDouble() ?? 0.0,
      eyeExpressionScore: (json['eye_expression_score'] as num?)?.toDouble() ?? 0.0,
      headMovementScore: (json['head_movement_score'] as num?)?.toDouble() ?? 0.0,
      facePresenceScore: (json['face_presence_score'] as num?)?.toDouble() ?? 0.0,
      faceChangeScore: (json['face_change_score'] as num?)?.toDouble() ?? 0.0,
      reactionScore: (json['reaction_score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
