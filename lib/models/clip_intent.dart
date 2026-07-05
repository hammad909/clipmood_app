enum ClipIntent {
  general,
  funny,
  sad,
  emotional,
  action,
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
      case ClipIntent.sad:
        return 'Sad';
      case ClipIntent.emotional:
        return 'Emotional';
      case ClipIntent.action:
        return 'Action';
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
      default:
        return label;
    }
  }

  String get helperText {
    switch (this) {
      case ClipIntent.general:
        return 'Finds a mixed tray: funny, sad, emotional, action, reaction, hooks, music, and highlights.';
      case ClipIntent.funny:
        return 'Prioritizes laughter, giggles, funny wording, smiles, and crowd reaction.';
      case ClipIntent.sad:
        return 'Prioritizes crying, sobbing, sad wording, pain/loss lines, and sad music.';
      case ClipIntent.emotional:
        return 'Prioritizes heartfelt lines, proud moments, gratitude, soft reactions, and tender music.';
      case ClipIntent.action:
        return 'Prioritizes crashes, bangs, fast motion, cuts, fights, chases, jumps, impacts, and sudden energy.';
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
      case ClipIntent.sad:
        return 'sad';
      case ClipIntent.emotional:
        return 'emotional';
      case ClipIntent.action:
        return 'action';
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

  String get audioPeakMood {
    switch (this) {
      case ClipIntent.funny:
        return 'funny';
      case ClipIntent.sad:
        return 'sad';
      case ClipIntent.emotional:
        return 'emotional';
      case ClipIntent.action:
        return 'action';
      case ClipIntent.podcastHook:
        return 'hook';
      case ClipIntent.sportsHighEnergy:
        return 'viral';
      case ClipIntent.musicEdit:
        return 'music';
      case ClipIntent.reaction:
        return 'reaction';
      case ClipIntent.general:
        return 'action';
    }
  }
}
