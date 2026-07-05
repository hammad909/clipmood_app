import 'dart:math';

import '../models/ai_signal.dart';
import '../models/clip_intent.dart';
import '../models/face_reaction_signal.dart';
import '../models/transcript_segment.dart';
import 'audio_peak_analyzer_service.dart';
import 'visual_highlight_analyzer_service.dart';
import 'yamnet_audio_classifier_service.dart';

class AiSignalBuilderService {
  List<AiSignal> buildSignals({
    required int durationSeconds,
    required ClipIntent intent,
    List<YamnetWindowResult> yamnetWindows = const [],
    List<AudioPeak> audioPeaks = const [],
    List<TranscriptSegment> transcriptSegments = const [],
    List<VisualFrameSignal> visualSignals = const [],
    List<FaceReactionFrameSignal> faceReactionSignals = const [],
  }) {
    final signals = <AiSignal>[];

    for (final window in yamnetWindows) {
      final signal = _signalFromYamnetWindow(window, intent: intent);
      if (signal != null) signals.add(signal);
    }

    for (final peak in audioPeaks) {
      final signal = _signalFromAudioPeak(
        peak,
        durationSeconds: durationSeconds,
        intent: intent,
      );
      if (signal != null) signals.add(signal);
    }

    for (final segment in transcriptSegments) {
      final signal = _signalFromTranscriptSegment(segment, intent: intent);
      if (signal != null) signals.add(signal);
    }

    for (final visual in visualSignals) {
      final signal = _signalFromVisualFrame(
        visual,
        durationSeconds: durationSeconds,
        intent: intent,
      );
      if (signal != null) signals.add(signal);
    }

    for (final faceReaction in faceReactionSignals) {
      final signal = _signalFromFaceReactionFrame(
        faceReaction,
        durationSeconds: durationSeconds,
        intent: intent,
      );
      if (signal != null) signals.add(signal);
    }

    signals.sort((a, b) {
      final timeCompare = a.startSeconds.compareTo(b.startSeconds);
      if (timeCompare != 0) return timeCompare;
      return b.weightedScore.compareTo(a.weightedScore);
    });

    return signals;
  }

  AiSignal? _signalFromYamnetWindow(
    YamnetWindowResult window, {
    required ClipIntent intent,
  }) {
    final moodScores = _emptyMoodScores(highlight: window.highlightScore);
    double silencePenalty = 0.0;
    double topPredictionScore = 0.0;
    final tags = <String>[];

    for (final prediction in window.predictions) {
      final label = prediction.label.toLowerCase();
      final value = prediction.score.clamp(0.0, 1.0).toDouble();
      topPredictionScore = max(topPredictionScore, value);

      if (_containsAny(label, const [
        'laughter',
        'giggle',
        'chuckle',
        'snicker',
        'belly laugh',
        'laugh',
      ])) {
        moodScores['funny'] = max(moodScores['funny']!, value * 1.42);
        moodScores['reaction'] = max(moodScores['reaction']!, value * 1.02);
        tags.add('laughter');
      }

      if (_containsAny(label, const [
        'crying',
        'sob',
        'sobbing',
        'wail',
        'whimper',
        'sad music',
        'melancholic',
        'tender music',
      ])) {
        moodScores['sad'] = max(moodScores['sad']!, value * 1.48);
        moodScores['emotional'] = max(moodScores['emotional']!, value * 1.18);
        moodScores['reaction'] = max(moodScores['reaction']!, value * 0.60);
        tags.add('sad / crying audio');
      }

      if (_containsAny(label, const [
        'sigh',
        'sobbing',
        'tender music',
        'soft music',
        'humming',
        'choir',
        'heartbeat',
      ])) {
        moodScores['emotional'] = max(moodScores['emotional']!, value * 1.20);
        tags.add('emotional audio');
      }

      if (_containsAny(label, const [
        'gunshot',
        'explosion',
        'boom',
        'bang',
        'blast',
        'crash',
        'slam',
        'smash',
        'impact',
        'thump',
        'slap',
        'punch',
        'hit',
        'vehicle',
        'engine',
        'motor',
        'revving',
        'siren',
        'whoosh',
        'swish',
        'thunder',
      ])) {
        moodScores['action'] = max(moodScores['action']!, value * 1.45);
        moodScores['viral'] = max(moodScores['viral']!, value * 0.90);
        tags.add('action sound');
      }

      if (_containsAny(label, const [
        'creak',
        'squeak',
        'scary music',
        'horror',
        'growling',
        'animal',
        'boing',
        'cartoon',
        'mysterious',
      ])) {
        moodScores['weird'] = max(moodScores['weird']!, value * 1.18);
        moodScores['reaction'] = max(moodScores['reaction']!, value * 0.70);
        tags.add('weird sound');
      }

      if (_containsAny(label, const [
        'cheering',
        'applause',
        'crowd',
        'shout',
        'yell',
        'scream',
        'whoop',
        'clapping',
        'chant',
      ])) {
        moodScores['viral'] = max(moodScores['viral']!, value * 1.30);
        moodScores['reaction'] = max(moodScores['reaction']!, value * 1.02);
        moodScores['action'] = max(moodScores['action']!, value * 0.62);
        tags.add('crowd / hype');
      }

      if (_containsAny(label, const [
        'speech',
        'conversation',
        'narration',
        'monologue',
        'dialogue',
        'talking',
        'chatter',
      ])) {
        moodScores['hook'] = max(moodScores['hook']!, value * 0.98);
        moodScores['highlight'] = max(moodScores['highlight']!, value * 0.48);
        tags.add('speech');
      }

      if (_containsAny(label, const [
        'music',
        'song',
        'singing',
        'beat',
        'drum',
        'bass',
        'dance',
        'hip hop',
        'electronic music',
        'rock music',
      ])) {
        moodScores['music'] = max(moodScores['music']!, value * 1.22);
        moodScores['exciting'] = max(moodScores['exciting']!, value * 1.02);
        tags.add('music');
      }

      if (label.contains('silence')) {
        silencePenalty = max(silencePenalty, value);
      }
    }

    final weightedScores = _applyIntentWeights(moodScores, intent);
    final best = _bestMood(weightedScores);
    final rawStrength = best.value - (silencePenalty * 0.45);
    final strength = rawStrength.clamp(0.0, 1.0).toDouble();

    if (silencePenalty >= 0.82 && strength < 0.18) {
      return AiSignal(
        startSeconds: window.startSecond,
        endSeconds: max(window.startSecond + 1, window.endSecond),
        source: AiSignalSource.audioEvent,
        mood: 'silence',
        strength: 0.05,
        confidence: silencePenalty,
        weight: 1.0,
        tags: const ['silence'],
        reasons: const ['Rejected/down-ranked because YAMNet detected mostly silence'],
        isNegative: true,
      );
    }

    final minStrength = intent == ClipIntent.general ? 0.075 : 0.10;
    if (strength < minStrength) return null;

    return AiSignal(
      startSeconds: window.startSecond,
      endSeconds: max(window.startSecond + 1, window.endSecond),
      source: AiSignalSource.audioEvent,
      mood: best.key,
      strength: strength,
      confidence: max(topPredictionScore, window.highlightScore).clamp(0.0, 1.0).toDouble(),
      weight: _sourceWeightForIntent(AiSignalSource.audioEvent, intent),
      tags: _uniqueStrings(tags).take(6).toList(),
      reasons: [
        'YAMNet detected useful audio event(s)',
        'Best audio category: ${best.key}',
        'Search intent: ${intent.label}',
      ],
      metadata: {
        'highlight_score': window.highlightScore,
        'silence_penalty': silencePenalty,
        'top_labels': window.predictions.take(5).map((p) => p.label).toList(),
      },
    );
  }

  AiSignal? _signalFromAudioPeak(
    AudioPeak peak, {
    required int durationSeconds,
    required ClipIntent intent,
  }) {
    // IMPORTANT:
    // A loud audio peak alone does NOT prove something is funny, sad,
    // emotional, a reaction, or a podcast hook. Earlier versions converted
    // peaks into the selected intent mood, which caused action/loud moments
    // to appear as Funny when the user selected Funny.
    //
    // Now peaks are only allowed as primary signals for categories where
    // loudness is actually meaningful by itself: Action, Sports/High Energy,
    // Music/Edit, and General.
    final peakMood = _standaloneAudioPeakMoodForIntent(intent);
    if (peakMood == null) return null;

    final threshold = intent == ClipIntent.musicEdit ? 0.055 : 0.070;
    if (peak.score < threshold) return null;

    final strength = ((peak.score - threshold) / 0.30).clamp(0.0, 1.0).toDouble();

    return AiSignal(
      startSeconds: peak.second,
      endSeconds: min(durationSeconds, peak.second + 1),
      source: AiSignalSource.audioPeak,
      mood: peakMood,
      strength: max(strength, peak.score.clamp(0.0, 1.0).toDouble()),
      confidence: peak.score >= 0.18 ? 0.78 : 0.58,
      weight: _sourceWeightForIntent(AiSignalSource.audioPeak, intent),
      tags: const ['loudness peak'],
      reasons: const [
        'Audio peak detected',
        'Used only for action, high-energy, music, or general highlights',
      ],
      metadata: {
        'rms_score': peak.score,
      },
    );
  }

  AiSignal? _signalFromTranscriptSegment(
    TranscriptSegment segment, {
    required ClipIntent intent,
  }) {
    if (!segment.isUsable) return null;

    final text = segment.normalizedText.toLowerCase();
    final moodScores = _emptyMoodScores(highlight: 0.05);
    final tags = <String>[];

    _addTextScore(
      text: text,
      moodScores: moodScores,
      tags: tags,
      mood: 'hook',
      tag: 'hook phrase',
      value: 0.34,
      patterns: const [
        'wait',
        'listen',
        'you need to know',
        'you won\'t believe',
        'most people',
        'biggest mistake',
        'the truth is',
        'here\'s why',
        'this is why',
        'secret',
        'important',
        'remember this',
        'what happened next',
        'let me explain',
        'nobody talks about',
      ],
    );

    _addTextScore(
      text: text,
      moodScores: moodScores,
      tags: tags,
      mood: 'info',
      tag: 'informative wording',
      value: 0.35,
      patterns: const [
        'how to',
        'tutorial',
        'step',
        'number one',
        'first thing',
        'second thing',
        'tip',
        'tips',
        'because',
        'the reason',
        'for example',
        'let me explain',
        'learn',
        'important',
        'fact',
        'facts',
        'mistake',
        'strategy',
        'method',
      ],
    );

    _addTextScore(
      text: text,
      moodScores: moodScores,
      tags: tags,
      mood: 'weird',
      tag: 'weird wording',
      value: 0.30,
      patterns: const [
        'weird',
        'strange',
        'awkward',
        'creepy',
        'confusing',
        'confused',
        'unexpected',
        'what is this',
        'why is',
        'that makes no sense',
        'this makes no sense',
        'unusual',
        'random',
        'scary',
      ],
    );

    _addTextScore(
      text: text,
      moodScores: moodScores,
      tags: tags,
      mood: 'funny',
      tag: 'comedy wording',
      value: 0.30,
      patterns: const [
        'funny',
        'joke',
        'haha',
        'laugh',
        'bro',
        'crazy',
        'what are you doing',
        'no way',
        'are you serious',
        'i can\'t believe',
        'that was wild',
        'embarrassing',
      ],
    );

    _addTextScore(
      text: text,
      moodScores: moodScores,
      tags: tags,
      mood: 'sad',
      tag: 'sad wording',
      value: 0.34,
      patterns: const [
        'cry',
        'crying',
        'tears',
        'lost',
        'loss',
        'miss you',
        'goodbye',
        'alone',
        'hurt',
        'pain',
        'sorry',
        'heartbreak',
        'broken',
        'never came back',
      ],
    );

    _addTextScore(
      text: text,
      moodScores: moodScores,
      tags: tags,
      mood: 'emotional',
      tag: 'emotional wording',
      value: 0.31,
      patterns: const [
        'love',
        'proud',
        'dream',
        'heart',
        'family',
        'mother',
        'father',
        'thank you',
        'grateful',
        'changed my life',
        'finally',
        'hope',
        'promise',
        'believe in yourself',
      ],
    );

    _addTextScore(
      text: text,
      moodScores: moodScores,
      tags: tags,
      mood: 'action',
      tag: 'action wording',
      value: 0.28,
      patterns: const [
        'run',
        'fight',
        'chase',
        'crash',
        'jump',
        'punch',
        'hit',
        'shot',
        'explosion',
        'race',
        'goal',
        'win',
        'attack',
        'escape',
      ],
    );

    _addTextScore(
      text: text,
      moodScores: moodScores,
      tags: tags,
      mood: 'viral',
      tag: 'strong statement',
      value: 0.27,
      patterns: const [
        'never',
        'always',
        'everyone',
        'nobody',
        'best',
        'worst',
        'first time',
        'last time',
        'million',
        'impossible',
        'changed everything',
      ],
    );

    if (text.contains('?')) {
      moodScores['hook'] = moodScores['hook']! + 0.20;
      tags.add('question');
    }

    if (text.contains('!')) {
      moodScores['reaction'] = moodScores['reaction']! + 0.12;
      moodScores['viral'] = moodScores['viral']! + 0.10;
      tags.add('strong delivery');
    }

    if (text.length >= 45 && text.length <= 190) {
      moodScores['hook'] = moodScores['hook']! + 0.08;
      moodScores['highlight'] = moodScores['highlight']! + 0.08;
      tags.add('quote-sized segment');
    }

    final weightedScores = _applyIntentWeights(moodScores, intent);
    final best = _bestMood(weightedScores);
    final strength = best.value.clamp(0.0, 1.0).toDouble();

    final minStrength = intent == ClipIntent.general ? 0.10 : 0.12;
    if (strength < minStrength) return null;

    return AiSignal(
      startSeconds: segment.startSeconds,
      endSeconds: max(segment.startSeconds + 1, segment.endSeconds),
      source: AiSignalSource.transcript,
      mood: best.key,
      strength: strength,
      confidence: segment.confidence.clamp(0.0, 1.0).toDouble(),
      weight: _sourceWeightForIntent(AiSignalSource.transcript, intent),
      tags: _uniqueStrings(tags).take(7).toList(),
      reasons: [
        'Transcript text contains useful meaning',
        'Best transcript category: ${best.key}',
        'Text: "${_shorten(segment.normalizedText, 90)}"',
      ],
      metadata: {
        'text': segment.normalizedText,
        'source': segment.source,
      },
    );
  }

  AiSignal? _signalFromVisualFrame(
    VisualFrameSignal signal, {
    required int durationSeconds,
    required ClipIntent intent,
  }) {
    final moodScores = _emptyMoodScores();
    moodScores['reaction'] = (signal.motionScore * 0.48) + (signal.sceneChangeScore * 0.36);
    moodScores['action'] = (signal.motionScore * 0.66) +
        (signal.sceneChangeScore * 0.30) +
        (signal.visualEnergyScore * 0.32);
    moodScores['viral'] = (signal.visualEnergyScore * 0.58) + (signal.motionScore * 0.28);
    moodScores['music'] = (signal.sceneChangeScore * 0.42) +
        (signal.brightnessChangeScore * 0.26) +
        (signal.visualEnergyScore * 0.25);
    moodScores['weird'] = (signal.brightnessChangeScore * 0.22) +
        (signal.sceneChangeScore * 0.18);
    moodScores['emotional'] = (signal.sceneChangeScore * 0.16) + ((1.0 - signal.brightnessScore) * 0.06);
    moodScores['highlight'] = signal.visualEnergyScore * 0.45;

    final weightedScores = _applyIntentWeights(moodScores, intent);
    final best = _bestMood(weightedScores);
    final strength = best.value.clamp(0.0, 1.0).toDouble();

    final minStrength = intent == ClipIntent.general ? 0.075 : 0.10;
    if (strength < minStrength) return null;

    final tags = <String>[
      if (signal.motionScore >= 0.12) 'motion',
      if (signal.sceneChangeScore >= 0.12) 'scene change',
      if (signal.brightnessChangeScore >= 0.10) 'brightness jump',
      if (signal.visualEnergyScore >= 0.12) 'visual energy',
    ];

    final source = signal.sceneChangeScore >= signal.motionScore &&
            signal.sceneChangeScore >= 0.16
        ? AiSignalSource.sceneChange
        : AiSignalSource.visualMotion;

    return AiSignal(
      startSeconds: signal.second,
      endSeconds: min(durationSeconds, signal.second + max(1, signal.sampleEverySeconds)),
      source: source,
      mood: best.key,
      strength: strength,
      confidence: max(signal.sceneChangeScore, signal.visualEnergyScore)
          .clamp(0.0, 1.0)
          .toDouble(),
      weight: _sourceWeightForIntent(source, intent),
      tags: tags,
      reasons: [
        source == AiSignalSource.sceneChange
            ? 'Visual scene change detected'
            : 'Visual motion/energy detected',
        'Useful for action, reaction, sports, music edit, and general highlight clips',
      ],
      metadata: {
        'motion': signal.motionScore,
        'scene_change': signal.sceneChangeScore,
        'brightness_change': signal.brightnessChangeScore,
        'visual_energy': signal.visualEnergyScore,
      },
    );
  }

  AiSignal? _signalFromFaceReactionFrame(
    FaceReactionFrameSignal signal, {
    required int durationSeconds,
    required ClipIntent intent,
  }) {
    if (!signal.hasFace) return null;

    final moodScores = _emptyMoodScores();
    moodScores['reaction'] = (signal.reactionScore * 0.72) +
        (signal.faceChangeScore * 0.20) +
        (signal.headMovementScore * 0.12);
    moodScores['funny'] = (signal.smilingScore * 0.88) +
        (signal.reactionScore * 0.24);
    moodScores['sad'] = ((1.0 - signal.smilingScore) * 0.18) +
        (signal.eyeExpressionScore * 0.18) +
        (signal.headMovementScore * 0.12);
    moodScores['emotional'] = ((1.0 - signal.smilingScore) * 0.16) +
        (signal.headMovementScore * 0.22) +
        (signal.facePresenceScore * 0.16) +
        (signal.eyeExpressionScore * 0.10);
    moodScores['viral'] = (signal.reactionScore * 0.48) +
        (signal.faceChangeScore * 0.30) +
        (signal.facePresenceScore * 0.14);
    moodScores['weird'] = (signal.faceChangeScore * 0.26) +
        (signal.eyeExpressionScore * 0.20) +
        ((1.0 - signal.smilingScore) * 0.08);
    moodScores['highlight'] = signal.reactionScore * 0.45;

    final weightedScores = _applyIntentWeights(moodScores, intent);
    final best = _bestMood(weightedScores);
    final strength = best.value.clamp(0.0, 1.0).toDouble();

    final minStrength = intent == ClipIntent.general ? 0.09 : 0.12;
    if (strength < minStrength) return null;

    final tags = <String>[
      if (signal.faceCount == 1) 'face detected',
      if (signal.faceCount > 1) '${signal.faceCount} faces detected',
      if (signal.smilingScore >= 0.35) 'smile / laugh face',
      if (signal.faceChangeScore >= 0.22) 'reaction change',
      if (signal.headMovementScore >= 0.25) 'head movement',
      if (signal.eyeExpressionScore >= 0.25) 'eye expression',
      if (signal.reactionScore >= 0.35) 'strong face reaction',
    ];

    return AiSignal(
      startSeconds: signal.second,
      endSeconds: min(durationSeconds, signal.second + max(1, signal.sampleEverySeconds)),
      source: AiSignalSource.faceReaction,
      mood: best.key,
      strength: strength,
      confidence: max(signal.reactionScore, signal.facePresenceScore)
          .clamp(0.0, 1.0)
          .toDouble(),
      weight: _sourceWeightForIntent(AiSignalSource.faceReaction, intent),
      tags: _uniqueStrings(tags).take(7).toList(),
      reasons: [
        'On-device face/reaction detector found expressive visual evidence',
        'Best face/reaction category: ${best.key}',
        'Useful for funny, sad, emotional, reaction, and viral clips',
      ],
      metadata: {
        'face_count': signal.faceCount,
        'smiling_score': signal.smilingScore,
        'eye_expression_score': signal.eyeExpressionScore,
        'head_movement_score': signal.headMovementScore,
        'face_change_score': signal.faceChangeScore,
        'reaction_score': signal.reactionScore,
      },
    );
  }

  Map<String, double> _emptyMoodScores({double highlight = 0.0}) {
    return {
      'funny': 0,
      'sad': 0,
      'emotional': 0,
      'action': 0,
      'hook': 0,
      'music': 0,
      'exciting': 0,
      'viral': 0,
      'reaction': 0,
      'weird': 0,
      'info': 0,
      'highlight': highlight,
    };
  }

  String? _standaloneAudioPeakMoodForIntent(ClipIntent intent) {
    switch (intent) {
      case ClipIntent.action:
        return 'action';
      case ClipIntent.sportsHighEnergy:
        return 'viral';
      case ClipIntent.musicEdit:
        return 'music';
      case ClipIntent.general:
        return 'viral';
      case ClipIntent.funny:
      case ClipIntent.sad:
      case ClipIntent.emotional:
      case ClipIntent.podcastHook:
      case ClipIntent.reaction:
        return null;
    }
  }

  Map<String, double> _applyIntentWeights(
    Map<String, double> scores,
    ClipIntent intent,
  ) {
    final result = Map<String, double>.from(scores);

    void boost(String mood, double multiplier) {
      result[mood] = (result[mood] ?? 0) * multiplier;
    }

    switch (intent) {
      case ClipIntent.funny:
        boost('funny', 1.85);
        boost('reaction', 1.18);
        boost('hook', 0.70);
        boost('sad', 0.28);
        boost('emotional', 0.42);
        break;
      case ClipIntent.sad:
        boost('sad', 2.05);
        boost('emotional', 1.18);
        boost('hook', 0.82);
        boost('funny', 0.22);
        boost('viral', 0.45);
        break;
      case ClipIntent.emotional:
        boost('emotional', 1.95);
        boost('sad', 1.15);
        boost('hook', 0.86);
        boost('funny', 0.32);
        boost('viral', 0.56);
        break;
      case ClipIntent.action:
        boost('action', 2.05);
        boost('viral', 1.24);
        boost('reaction', 1.18);
        boost('music', 0.62);
        boost('sad', 0.32);
        boost('emotional', 0.35);
        break;
      case ClipIntent.podcastHook:
        boost('hook', 2.10);
        boost('highlight', 1.15);
        boost('viral', 0.70);
        boost('funny', 0.45);
        boost('action', 0.45);
        break;
      case ClipIntent.sportsHighEnergy:
        boost('viral', 1.92);
        boost('action', 1.45);
        boost('reaction', 1.32);
        boost('exciting', 1.20);
        boost('music', 0.82);
        boost('emotional', 0.35);
        break;
      case ClipIntent.musicEdit:
        boost('music', 2.00);
        boost('exciting', 1.62);
        boost('viral', 1.12);
        boost('reaction', 0.72);
        boost('hook', 0.40);
        break;
      case ClipIntent.reaction:
        boost('reaction', 1.92);
        boost('funny', 1.15);
        boost('viral', 1.10);
        boost('sad', 1.02);
        boost('emotional', 0.98);
        boost('action', 0.92);
        break;
      case ClipIntent.general:
        boost('highlight', 0.82);
        boost('funny', 1.08);
        boost('sad', 1.06);
        boost('emotional', 1.06);
        boost('action', 1.08);
        boost('hook', 1.07);
        boost('info', 1.07);
        boost('music', 1.05);
        boost('reaction', 1.06);
        boost('weird', 1.05);
        boost('viral', 1.05);
        break;
    }

    return result.map((key, value) {
      return MapEntry(key, value.clamp(0.0, 1.0).toDouble());
    });
  }

  double _sourceWeightForIntent(AiSignalSource source, ClipIntent intent) {
    switch (source) {
      case AiSignalSource.transcript:
        return intent == ClipIntent.podcastHook ? 1.60 : 1.25;
      case AiSignalSource.faceReaction:
        return intent == ClipIntent.reaction ||
                intent == ClipIntent.funny ||
                intent == ClipIntent.sad ||
                intent == ClipIntent.emotional
            ? 1.55
            : 1.22;
      case AiSignalSource.audioEvent:
        return intent == ClipIntent.funny ||
                intent == ClipIntent.sportsHighEnergy ||
                intent == ClipIntent.action ||
                intent == ClipIntent.sad
            ? 1.30
            : 1.10;
      case AiSignalSource.audioPeak:
        return intent == ClipIntent.musicEdit ||
                intent == ClipIntent.sportsHighEnergy ||
                intent == ClipIntent.action
            ? 1.10
            : 0.82;
      case AiSignalSource.sceneChange:
        return intent == ClipIntent.musicEdit ||
                intent == ClipIntent.reaction ||
                intent == ClipIntent.action
            ? 1.20
            : 0.94;
      case AiSignalSource.visualMotion:
        return intent == ClipIntent.reaction ||
                intent == ClipIntent.sportsHighEnergy ||
                intent == ClipIntent.action
            ? 1.15
            : 0.90;
      case AiSignalSource.userFeedback:
        return 1.60;
    }
  }

  void _addTextScore({
    required String text,
    required Map<String, double> moodScores,
    required List<String> tags,
    required String mood,
    required String tag,
    required double value,
    required List<String> patterns,
  }) {
    for (final pattern in patterns) {
      if (text.contains(pattern)) {
        moodScores[mood] = (moodScores[mood] ?? 0) + value;
        tags.add(tag);
        return;
      }
    }
  }

  MapEntry<String, double> _bestMood(Map<String, double> scores) {
    final entries = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return entries.isEmpty ? const MapEntry('highlight', 0.0) : entries.first;
  }

  bool _containsAny(String text, List<String> needles) {
    for (final needle in needles) {
      if (text.contains(needle)) return true;
    }
    return false;
  }

  List<String> _uniqueStrings(List<String> values) {
    final seen = <String>{};
    final result = <String>[];

    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed.toLowerCase())) result.add(trimmed);
    }

    return result;
  }

  String _shorten(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength - 3)}...';
  }
}
