/// Helpers for the "ক. " style label in front of an MCQ option.
///
/// Options reach the app with the label already baked into the text as often
/// as not: a scanned book page keeps whatever was printed, and the prompts'
/// own examples show options written as "ক. সুধাকর". Code that renders or
/// exports options adds its own label, so without stripping first the result
/// reads "ক. ক. সুধাকর".
library;

final _leadingLabel = RegExp(r'^\s*[কখগঘঙa-eA-E১২৩৪৫1-5]\s*[.)।:\-]\s+');

/// The option without the label it was printed with, if it had one.
String stripOptionLabel(String option) {
  final stripped = option.replaceFirst(_leadingLabel, '');
  // An option that is nothing but its label is not a label: keep the text.
  return stripped.trim().isEmpty ? option.trim() : stripped.trim();
}

/// The Bengali letter for a zero-based option position.
String optionLabelChar(int index) {
  const labels = ['ক', 'খ', 'গ', 'ঘ', 'ঙ', 'চ'];
  return index >= 0 && index < labels.length ? labels[index] : '${index + 1}';
}

/// The option with exactly one label in front of it.
String labelledOption(int index, String option) =>
    '${optionLabelChar(index)}. ${stripOptionLabel(option)}';
