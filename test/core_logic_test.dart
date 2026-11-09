import 'package:flutter_test/flutter_test.dart';
import 'package:taleemplus_app/logic/text_rank_summarizer.dart';
import 'package:taleemplus_app/logic/tfidf_grader.dart';
import 'package:taleemplus_app/core/utils/validators.dart';

void main() {
  group('Password validation', () {
    test('requires eight characters and rejects common passwords', () {
      expect(Validators.password('short7'), isNotNull);
      expect(Validators.password('Password123'), isNotNull);
    });

    test('accepts a non-common password of sufficient length', () {
      expect(Validators.password('Academy!7Term'), isNull);
    });

    test('login validation preserves existing passwords of any nonempty length',
        () {
      expect(Validators.passwordForLogin('old'), isNull);
      expect(Validators.passwordForLogin(''), isNotNull);
    });
  });

  group('TfIdfGrader', () {
    test('scores matching answer terms above unrelated terms', () {
      const keywords = ['photosynthesis', 'chlorophyll'];
      const corpus = [
        keywords,
        ['gravity', 'mass']
      ];

      final matching = TfIdfGrader.score(
        keywords: keywords,
        answerText: 'Chlorophyll enables photosynthesis.',
        corpusKeywordSets: corpus,
      );
      final unrelated = TfIdfGrader.score(
        keywords: keywords,
        answerText: 'Planets orbit because of gravity.',
        corpusKeywordSets: corpus,
      );

      expect(matching, greaterThan(unrelated));
      expect(unrelated, 0);
    });

    test('returns zero when no grading keywords are configured', () {
      expect(
        TfIdfGrader.score(
          keywords: const [],
          answerText: 'Any answer text',
          corpusKeywordSets: const [],
        ),
        0,
      );
    });

    test('tokenizes phrases and normalizes Urdu Arabic letter variants', () {
      final score = TfIdfGrader.score(
        keywords: const ['قدرتی سائنس', 'کتاب'],
        answerText: 'قدرتی سائنس کتاب',
        corpusKeywordSets: const [
          ['قدرتی سائنس', 'کتاب'],
          ['ریاضی'],
        ],
      );
      expect(score, greaterThan(0));
      expect(score, lessThanOrEqualTo(1));
    });
  });

  test('TextRank summary respects the requested sentence limit', () {
    const notes = 'Plants use sunlight to make food through photosynthesis. '
        'Chlorophyll in plant leaves absorbs light for photosynthesis. '
        'The process produces sugars that plants use for energy. '
        'Water and carbon dioxide are also needed for this process.';

    final summary = TextRankSummarizer.summarize(notes, maxSentences: 2);

    expect(summary, hasLength(2));
    expect(summary.every(notes.contains), isTrue);
  });

  test('TextRank joins OCR hyphenation and removes duplicate sentences', () {
    const notes =
        'Photosyn-\nthesis converts sunlight into stored chemical energy. '
        'Leaves contain chlorophyll, which captures sunlight for the process. '
        'Photosynthesis converts sunlight into stored chemical energy.';
    final ranked = TextRankSummarizer.rankSentences(notes);
    expect(ranked, hasLength(2));
    expect(ranked.first, contains('Photosynthesis'));
    expect(TextRankSummarizer.summarize(notes, maxSentences: 0), isEmpty);
  });

  test('TextRank recognizes Urdu sentence punctuation and vocabulary', () {
    const notes =
        'یہ ایک اہم سائنسی عمل ہے۔ پودے روشنی سے توانائی حاصل کرتے ہیں۔';
    expect(TextRankSummarizer.rankSentences(notes), hasLength(2));
  });
}
