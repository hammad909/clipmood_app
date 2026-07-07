enum ClipIntent {
  general,
  funny,
  happy,
  sad,
  emotional,
  romantic,
  angry,
  action,
  fight,
  weird,
  entertaining,
  podcastHook,
  sportsHighEnergy,
  musicEdit,
  reaction,
}

extension ClipIntentX on ClipIntent {
  String get label {
    switch (this) {
      case ClipIntent.general:
        return 'General';
      case ClipIntent.funny:
        return 'Funny';
      case ClipIntent.happy:
        return 'Happy';
      case ClipIntent.sad:
        return 'Sad';
      case ClipIntent.emotional:
        return 'Emotional';
      case ClipIntent.romantic:
        return 'Romantic';
      case ClipIntent.angry:
        return 'Angry';
      case ClipIntent.action:
        return 'Action';
      case ClipIntent.fight:
        return 'Fight';
      case ClipIntent.weird:
        return 'Weird';
      case ClipIntent.entertaining:
        return 'Entertaining';
      case ClipIntent.podcastHook:
        return 'Podcast Hook';
      case ClipIntent.sportsHighEnergy:
        return 'Sports / High Energy';
      case ClipIntent.musicEdit:
        return 'Music Edit';
      case ClipIntent.reaction:
        return 'Reaction';
    }
  }

  String get shortLabel {
    switch (this) {
      case ClipIntent.sportsHighEnergy:
        return 'Sports';
      case ClipIntent.podcastHook:
        return 'Hook';
      case ClipIntent.musicEdit:
        return 'Music';
      case ClipIntent.entertaining:
        return 'Entertain';
      default:
        return label;
    }
  }

  String get helperText {
    switch (this) {
      case ClipIntent.general:
        return 'Finds a mixed tray: funny, happy, sad, emotional, romantic, angry, action, fight, weird, entertaining, reaction, hooks, music, and highlights.';
      case ClipIntent.funny:
        return 'Prioritizes laughter, jokes, comedy wording, smiles, and funny reactions.';
      case ClipIntent.happy:
        return 'Prioritizes smiles, celebration, joy, good news, cheering, and positive reactions.';
      case ClipIntent.sad:
        return 'Prioritizes crying, sobbing, sad wording, pain/loss lines, and sad music.';
      case ClipIntent.emotional:
        return 'Prioritizes heartfelt lines, proud moments, gratitude, family, soft reactions, and tender music.';
      case ClipIntent.romantic:
        return 'Prioritizes love, couples, wedding/romantic wording, soft/tender music, and affectionate moments.';
      case ClipIntent.angry:
        return 'Prioritizes anger, arguments, shouting, aggressive wording, intense reactions, and conflict sounds.';
      case ClipIntent.action:
        return 'Prioritizes crashes, bangs, fast motion, cuts, chases, jumps, impacts, and sudden energy.';
      case ClipIntent.fight:
        return 'Prioritizes punches, hits, fights, attacks, arguments turning physical, impacts, and high motion.';
      case ClipIntent.weird:
        return 'Prioritizes strange, awkward, creepy, confusing, unexpected, or unusual moments.';
      case ClipIntent.entertaining:
        return 'Prioritizes fun, high-retention moments with laughter, music, crowd energy, reactions, or visual movement.';
      case ClipIntent.podcastHook:
        return 'Prioritizes speech-heavy hooks, strong quotes, questions, and important statements.';
      case ClipIntent.sportsHighEnergy:
        return 'Prioritizes cheering, applause, shouting, screams, crowd hype, goals, wins, and high motion.';
      case ClipIntent.musicEdit:
        return 'Prioritizes music, beats, bass, singing, rhythm, scene cuts, and strong audio peaks.';
      case ClipIntent.reaction:
        return 'Prioritizes faces, smiles, shouting, crying, cheering, sudden changes, and reaction energy.';
    }
  }

  String get defaultMood {
    switch (this) {
      case ClipIntent.funny:
        return 'funny';
      case ClipIntent.happy:
        return 'happy';
      case ClipIntent.sad:
        return 'sad';
      case ClipIntent.emotional:
        return 'emotional';
      case ClipIntent.romantic:
        return 'romantic';
      case ClipIntent.angry:
        return 'angry';
      case ClipIntent.action:
        return 'action';
      case ClipIntent.fight:
        return 'fight';
      case ClipIntent.weird:
        return 'weird';
      case ClipIntent.entertaining:
        return 'entertaining';
      case ClipIntent.podcastHook:
        return 'hook';
      case ClipIntent.sportsHighEnergy:
        return 'viral';
      case ClipIntent.musicEdit:
        return 'music';
      case ClipIntent.reaction:
        return 'reaction';
      case ClipIntent.general:
        return 'highlight';
    }
  }

  /// Used by older UI code. Audio peaks alone should still be treated carefully
  /// by AiSignalBuilderService; this value is only a fallback label.
  String get audioPeakMood {
    switch (this) {
      case ClipIntent.action:
        return 'action';
      case ClipIntent.fight:
        return 'fight';
      case ClipIntent.sportsHighEnergy:
      case ClipIntent.entertaining:
        return 'viral';
      case ClipIntent.musicEdit:
        return 'music';
      case ClipIntent.general:
        return 'action';
      default:
        return defaultMood;
    }
  }
}
