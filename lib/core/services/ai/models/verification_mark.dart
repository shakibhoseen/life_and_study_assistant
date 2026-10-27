/// How a stored question was last checked.
///
/// Kept deliberately coarse. The point is to say who stood behind the answer,
/// not to replay the whole verification: a mark the user put there means more
/// than one a model put there, and the two must never look alike.
enum VerificationMark {
  /// The user said so themselves.
  userVerified,

  /// A verifier reached the same answer on its own. Two opinions, not proof.
  modelAgreed,

  /// Something is wrong with the question, and it has not been fixed yet.
  flagged,

  none;

  static VerificationMark parse(String? raw) => switch ((raw ?? '').trim()) {
    'user_verified' => VerificationMark.userVerified,
    'model_agreed' => VerificationMark.modelAgreed,
    'flagged' => VerificationMark.flagged,
    _ => VerificationMark.none,
  };

  String get storageKey => switch (this) {
    VerificationMark.userVerified => 'user_verified',
    VerificationMark.modelAgreed => 'model_agreed',
    VerificationMark.flagged => 'flagged',
    VerificationMark.none => '',
  };

  String get label => switch (this) {
    VerificationMark.userVerified => 'আপনি যাচাই করেছেন',
    VerificationMark.modelAgreed => 'যাচাইকারী একমত',
    VerificationMark.flagged => 'সমস্যা চিহ্নিত',
    VerificationMark.none => '',
  };

  /// Only the user's own mark is treated as settled; the model's is a note
  /// about what happened, not a guarantee.
  bool get isTrusted => this == VerificationMark.userVerified;
}
