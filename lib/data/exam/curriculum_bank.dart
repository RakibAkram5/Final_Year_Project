import '../models/quiz_model.dart';

/// A single curriculum-authored question template. Carries everything needed
/// to materialise a [QuizQuestion] plus its teacher answer, so generated
/// papers are backed by real, vetted content rather than fabricated text.
class BankItem {
  final QuestionType type;
  final String chapter;
  final String text;
  final List<String>? options; // MCQ only
  final int? correctIndex; // MCQ only
  final String answer; // model answer / correct option text
  final List<String> keywords;
  final String difficulty; // 'Easy' | 'Medium' | 'Hard'

  const BankItem({
    required this.type,
    required this.chapter,
    required this.text,
    this.options,
    this.correctIndex,
    required this.answer,
    this.keywords = const [],
    this.difficulty = 'Medium',
  });
}

/// Offline curriculum question bank for the subjects the product ships with
/// vetted content for (Pakistani 9th-class syllabus style). The generator
/// uses this when no scanned/uploaded source material is supplied and no LLM
/// is configured, so a teacher can still produce a real Computer Science,
/// Mathematics or English paper out of the box.
///
/// Subjects are matched case-insensitively on a keyword in the subject name
/// (e.g. "Computer Science", "Comp Sci", "Maths", "English Language").
class CurriculumBank {
  const CurriculumBank._();

  /// Returns the bank for [subject], or null when no vetted content exists —
  /// the generator then tells the teacher instead of inventing questions.
  static List<BankItem>? forSubject(String subject) {
    final s = subject.toLowerCase();
    if (s.contains('comp') || s.contains('ict') || s.contains('computer')) {
      return _computerScience;
    }
    if (s.contains('math')) return _mathematics;
    if (s.contains('eng')) return _english;
    return null;
  }

  static bool hasSubject(String subject) => forSubject(subject) != null;

  /// Distinct chapter labels available for [subject].
  static List<String> chaptersFor(String subject) {
    final bank = forSubject(subject);
    if (bank == null) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final item in bank) {
      if (seen.add(item.chapter)) out.add(item.chapter);
    }
    return out;
  }

  // ----------------------- Computer Science (9th) -----------------------
  static const List<BankItem> _computerScience = [
    // --- Data and number systems ---
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Data and Number Systems',
      text: 'Which number system uses only the digits 0 and 1?',
      options: ['Decimal', 'Binary', 'Octal', 'Hexadecimal'],
      correctIndex: 1,
      answer: 'Binary',
      keywords: ['binary', 'base 2', '0', '1'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Data and Number Systems',
      text: 'The base (radix) of the hexadecimal number system is:',
      options: ['2', '8', '10', '16'],
      correctIndex: 3,
      answer: '16',
      keywords: ['hexadecimal', 'base 16', 'radix'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Data and Number Systems',
      text: 'The decimal number 10 is represented in binary as:',
      options: ['1010', '1100', '1001', '1110'],
      correctIndex: 0,
      answer: '1010',
      keywords: ['binary', 'conversion', 'decimal'],
      difficulty: 'Medium',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Data and Number Systems',
      text: 'How many bits make one byte?',
      options: ['4', '8', '16', '32'],
      correctIndex: 1,
      answer: '8',
      keywords: ['byte', 'bits', '8'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Data and Number Systems',
      text: 'Which code uses 16 bits and can represent characters of most '
          'of the world\'s writing systems?',
      options: ['ASCII', 'BCD', 'Unicode', 'EBCDIC'],
      correctIndex: 2,
      answer: 'Unicode',
      keywords: ['unicode', '16 bit', 'characters'],
      difficulty: 'Medium',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Data and Number Systems',
      text: 'The 1\'s complement of the binary number 1010 is:',
      options: ['0101', '1011', '0110', '1101'],
      correctIndex: 0,
      answer: '0101',
      keywords: ['ones complement', 'invert', 'binary'],
      difficulty: 'Medium',
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Data and Number Systems',
      text: 'Define Unicode.',
      answer: 'Unicode is a 16-bit character encoding standard that assigns a '
          'unique number (code point) to every character of almost all the '
          'writing systems of the world, allowing text in many languages to '
          'be represented consistently.',
      keywords: ['unicode', '16 bit', 'character', 'encoding', 'code point'],
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Data and Number Systems',
      text: 'Convert the decimal number 2297 to hexadecimal.',
      answer: '2297 ÷ 16 = 143 remainder 9; 143 ÷ 16 = 8 remainder 15 (F); '
          '8 ÷ 16 = 0 remainder 8. Reading remainders bottom-up gives 8F9. '
          'So (2297)10 = (8F9)16.',
      keywords: ['hexadecimal', 'conversion', '8f9', 'remainder'],
      difficulty: 'Hard',
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Data and Number Systems',
      text: 'What is the 1\'s complement of a binary number?',
      answer: 'The 1\'s complement of a binary number is obtained by inverting '
          '(flipping) every bit — changing each 0 to 1 and each 1 to 0.',
      keywords: ['ones complement', 'invert', 'flip', 'bits'],
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Data and Number Systems',
      text: 'What is the difference between UTF-8 and UTF-16?',
      answer:
          'Both are Unicode encodings. UTF-8 uses a variable length of 1 to 4 '
          'bytes per character and is backward compatible with ASCII, while '
          'UTF-16 uses 2 or 4 bytes per character. UTF-8 is more space '
          'efficient for English text; UTF-16 can be more efficient for '
          'scripts with large character sets.',
      keywords: ['utf-8', 'utf-16', 'bytes', 'encoding', 'variable'],
      difficulty: 'Hard',
    ),
    BankItem(
      type: QuestionType.long,
      chapter: 'Data and Number Systems',
      text: 'Explain how characters are encoded using Unicode. Also provide '
          'examples.',
      answer:
          'Unicode assigns a unique code point to every character. Each code '
          'point is written as U+ followed by a hexadecimal value, e.g. U+0041 '
          'for "A" and U+0631 for an Urdu letter. These code points are '
          'stored in memory using an encoding form such as UTF-8 or UTF-16. '
          'Marking: definition of code point (2), U+ hexadecimal notation (2), '
          'relationship to UTF-8/UTF-16 storage (2), at least two correct '
          'examples (2).',
      keywords: ['unicode', 'code point', 'utf', 'hexadecimal', 'example'],
      difficulty: 'Hard',
    ),

    // --- Computer hardware / architecture ---
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Computer Architecture',
      text: 'The part of the CPU that performs arithmetic and logic '
          'operations is the:',
      options: ['Control Unit', 'Arithmetic Logic Unit', 'Register', 'Cache'],
      correctIndex: 1,
      answer: 'Arithmetic Logic Unit',
      keywords: ['alu', 'arithmetic', 'logic'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Computer Architecture',
      text: 'In the Von Neumann architecture, program instructions and data '
          'are stored in:',
      options: [
        'Separate memories',
        'The same memory',
        'The ALU',
        'The hard disk only'
      ],
      correctIndex: 1,
      answer: 'The same memory',
      keywords: ['von neumann', 'stored program', 'memory'],
      difficulty: 'Medium',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Computer Architecture',
      text: 'Which unit coordinates and controls the operations of all parts '
          'of the computer?',
      options: ['ALU', 'Control Unit', 'RAM', 'Register'],
      correctIndex: 1,
      answer: 'Control Unit',
      keywords: ['control unit', 'cpu', 'coordinate'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Computer Architecture',
      text: 'What is the function of the Arithmetic Logic Unit (ALU)?',
      answer: 'The ALU is the part of the CPU that performs all arithmetic '
          'operations (addition, subtraction, etc.) and all logical operations '
          '(AND, OR, NOT, comparisons) on data.',
      keywords: ['alu', 'arithmetic', 'logic', 'cpu', 'operations'],
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Computer Architecture',
      text: 'What is a key advantage of the Von Neumann architecture?',
      answer: 'Because instructions and data share the same memory (the '
          'stored-program concept), the design is simpler and more flexible: '
          'programs can be loaded, changed and executed without rewiring the '
          'hardware.',
      keywords: ['von neumann', 'stored program', 'flexible', 'memory'],
    ),
    BankItem(
      type: QuestionType.long,
      chapter: 'Computer Architecture',
      text: 'Explain the working of the Von Neumann Architecture.',
      answer:
          'Von Neumann architecture is based on the stored-program concept. '
          'It has a CPU (containing the Control Unit and ALU), a single main '
          'memory holding both instructions and data, and input/output units, '
          'connected by a system bus. The CPU repeatedly performs the '
          'fetch-decode-execute cycle: the Control Unit fetches an instruction '
          'from memory, decodes it, and the ALU executes it, writing results '
          'back to memory or registers. Marking: stored-program concept (2), '
          'components CU/ALU/memory/IO (3), fetch-decode-execute cycle (3).',
      keywords: [
        'von neumann',
        'fetch',
        'decode',
        'execute',
        'control unit',
        'alu'
      ],
      difficulty: 'Hard',
    ),
    BankItem(
      type: QuestionType.long,
      chapter: 'Computer Architecture',
      text: 'Describe the basic concept of a system.',
      answer: 'A system is a collection of interrelated components that work '
          'together to achieve a common goal. Every system takes inputs, '
          'processes them and produces outputs, often with feedback to control '
          'the process. A computer system, for example, consists of hardware, '
          'software and users working together. Marking: definition (2), '
          'input-process-output model (3), feedback/example (3).',
      keywords: ['system', 'input', 'process', 'output', 'feedback'],
      difficulty: 'Medium',
    ),

    // --- Programming / problem solving ---
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Problem Solving',
      text: 'A step-by-step procedure to solve a problem is called a(n):',
      options: ['Flowchart', 'Algorithm', 'Program', 'Loop'],
      correctIndex: 1,
      answer: 'Algorithm',
      keywords: ['algorithm', 'steps', 'procedure'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Problem Solving',
      text: 'Which symbol is used to represent a decision in a flowchart?',
      options: ['Rectangle', 'Diamond', 'Oval', 'Parallelogram'],
      correctIndex: 1,
      answer: 'Diamond',
      keywords: ['flowchart', 'decision', 'diamond'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Problem Solving',
      text: 'The oval symbol in a flowchart represents:',
      options: ['Process', 'Input/Output', 'Start/Stop', 'Decision'],
      correctIndex: 2,
      answer: 'Start/Stop',
      keywords: ['flowchart', 'oval', 'terminal', 'start', 'stop'],
      difficulty: 'Medium',
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Problem Solving',
      text: 'Define an algorithm.',
      answer:
          'An algorithm is a finite, ordered sequence of well-defined steps '
          'that solves a particular problem or performs a task, taking some '
          'input and producing the required output.',
      keywords: ['algorithm', 'steps', 'finite', 'input', 'output'],
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Problem Solving',
      text: 'What is the difference between a flowchart and an algorithm?',
      answer: 'An algorithm expresses the solution steps in words/pseudocode, '
          'while a flowchart is a graphical representation of those steps using '
          'standard symbols connected by arrows.',
      keywords: ['flowchart', 'algorithm', 'graphical', 'symbols'],
    ),

    // --- Networks ---
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Networks',
      text: 'A network that covers a small area such as a single building is '
          'called a:',
      options: ['WAN', 'MAN', 'LAN', 'PAN'],
      correctIndex: 2,
      answer: 'LAN',
      keywords: ['lan', 'local', 'network'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Networks',
      text: 'Which device connects two or more networks and routes data '
          'between them?',
      options: ['Hub', 'Switch', 'Router', 'Repeater'],
      correctIndex: 2,
      answer: 'Router',
      keywords: ['router', 'network', 'route'],
      difficulty: 'Medium',
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Networks',
      text: 'Define a computer network.',
      answer:
          'A computer network is a group of two or more computers and devices '
          'connected together so that they can share data, resources and '
          'communicate with one another.',
      keywords: ['network', 'share', 'resources', 'communicate'],
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Data and Number Systems',
      text: 'What is the difference between a bit and a byte?',
      answer:
          'A bit is the smallest unit of data and is either 0 or 1. A byte is '
          'a group of 8 bits and can represent one character.',
      keywords: ['bit', 'byte', '8 bits', 'character'],
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Data and Number Systems',
      text: 'Define the ASCII code.',
      answer: 'ASCII (American Standard Code for Information Interchange) is a '
          '7-bit character encoding scheme that represents English letters, '
          'digits and control characters as numbers.',
      keywords: ['ascii', '7 bit', 'encoding', 'character'],
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Computer Architecture',
      text: 'What is the difference between RAM and ROM?',
      answer: 'RAM is volatile read/write memory that loses its contents when '
          'power is off; ROM is non-volatile memory whose contents are '
          'permanent and mainly readable.',
      keywords: ['ram', 'rom', 'volatile', 'non-volatile'],
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Computer Architecture',
      text: 'What is the function of the Control Unit?',
      answer: 'The Control Unit directs and coordinates the operations of the '
          'computer by fetching, decoding and controlling the execution of '
          'instructions.',
      keywords: ['control unit', 'fetch', 'decode', 'coordinate'],
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Problem Solving',
      text: 'What is pseudocode?',
      answer:
          'Pseudocode is an informal, language-independent way of describing '
          'the steps of an algorithm using plain English-like statements.',
      keywords: ['pseudocode', 'algorithm', 'steps', 'informal'],
    ),
    BankItem(
      type: QuestionType.long,
      chapter: 'Networks',
      text: 'Differentiate between LAN, MAN and WAN with examples.',
      answer:
          'LAN (Local Area Network) covers a small area like a building (e.g. '
          'a school lab). MAN (Metropolitan Area Network) spans a city (e.g. a '
          'city cable network). WAN (Wide Area Network) covers large '
          'geographical areas, even countries (e.g. the Internet). Marking: '
          'each type correctly described with coverage (2 each) + a valid '
          'example (2).',
      keywords: ['lan', 'man', 'wan', 'coverage', 'internet'],
      difficulty: 'Medium',
    ),

    // --- Additional MCQs (ensures a full 20-MCQ paper is possible) ---
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Data and Number Systems',
      text: 'The binary equivalent of the decimal number 7 is:',
      options: ['110', '111', '101', '011'],
      correctIndex: 1,
      answer: '111',
      keywords: ['binary', 'conversion', 'seven'],
      difficulty: 'Medium',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Data and Number Systems',
      text: 'Which of the following is a valid hexadecimal digit?',
      options: ['G', 'F', 'K', 'Z'],
      correctIndex: 1,
      answer: 'F',
      keywords: ['hexadecimal', 'digit', 'f'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Data and Number Systems',
      text: '1 Kilobyte (KB) is equal to:',
      options: ['1000 bytes', '1024 bytes', '8 bytes', '512 bytes'],
      correctIndex: 1,
      answer: '1024 bytes',
      keywords: ['kilobyte', '1024', 'bytes'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Computer Architecture',
      text: 'Which of the following is a volatile memory?',
      options: ['ROM', 'RAM', 'Hard Disk', 'DVD'],
      correctIndex: 1,
      answer: 'RAM',
      keywords: ['ram', 'volatile', 'memory'],
      difficulty: 'Medium',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Computer Architecture',
      text: 'The brain of the computer is the:',
      options: ['Monitor', 'CPU', 'Keyboard', 'RAM'],
      correctIndex: 1,
      answer: 'CPU',
      keywords: ['cpu', 'processor', 'brain'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Problem Solving',
      text: 'A rectangle in a flowchart represents a:',
      options: ['Decision', 'Process', 'Terminal', 'Connector'],
      correctIndex: 1,
      answer: 'Process',
      keywords: ['flowchart', 'rectangle', 'process'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Problem Solving',
      text: 'A loop that repeats a block of statements is an example of:',
      options: ['Sequence', 'Selection', 'Iteration', 'Declaration'],
      correctIndex: 2,
      answer: 'Iteration',
      keywords: ['loop', 'iteration', 'repeat'],
      difficulty: 'Medium',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Networks',
      text: 'The physical path over which data travels in a network is '
          'called the:',
      options: ['Protocol', 'Transmission medium', 'Topology', 'Packet'],
      correctIndex: 1,
      answer: 'Transmission medium',
      keywords: ['transmission', 'medium', 'network'],
      difficulty: 'Medium',
    ),
  ];

  // --------------------------- Mathematics (9th) ---------------------------
  static const List<BankItem> _mathematics = [
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Real Numbers',
      text: 'Which of the following is an irrational number?',
      options: ['0.25', 'Square root of 2', '3/4', '7'],
      correctIndex: 1,
      answer: 'Square root of 2 (a non-terminating, non-repeating decimal).',
      keywords: ['irrational', 'root 2', 'real numbers'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Real Numbers',
      text: 'The value of 2³ is:',
      options: ['6', '8', '9', '12'],
      correctIndex: 1,
      answer: '8',
      keywords: ['exponent', 'power', '8'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Algebraic Expressions',
      text: 'The expansion of (a + b)² is:',
      options: ['a² + b²', 'a² + 2ab + b²', 'a² - 2ab + b²', 'a² + ab + b²'],
      correctIndex: 1,
      answer: 'a² + 2ab + b²',
      keywords: ['expansion', 'square', 'identity'],
      difficulty: 'Medium',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Linear Equations',
      text: 'The solution of the equation 2x + 6 = 0 is:',
      options: ['x = 3', 'x = -3', 'x = 6', 'x = -6'],
      correctIndex: 1,
      answer: 'x = -3',
      keywords: ['linear equation', 'solve', 'x'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Matrices',
      text: 'A matrix with equal number of rows and columns is called a:',
      options: ['Row matrix', 'Column matrix', 'Square matrix', 'Null matrix'],
      correctIndex: 2,
      answer: 'Square matrix',
      keywords: ['matrix', 'square', 'rows', 'columns'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Geometry',
      text: 'The sum of the interior angles of a triangle is:',
      options: ['90°', '180°', '270°', '360°'],
      correctIndex: 1,
      answer: '180°',
      keywords: ['triangle', 'angles', '180'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Real Numbers',
      text: 'Define a rational number with one example.',
      answer:
          'A rational number is a number that can be written in the form p/q '
          'where p and q are integers and q is not equal to 0, e.g. 3/4 or 5.',
      keywords: ['rational', 'p/q', 'integer', 'example'],
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Algebraic Expressions',
      text: 'Factorize: x² - 9.',
      answer:
          'x² - 9 is a difference of two squares: x² - 3² = (x - 3)(x + 3).',
      keywords: ['factorize', 'difference of squares', 'x-3', 'x+3'],
      difficulty: 'Medium',
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Linear Equations',
      text: 'Solve for x: 3x - 7 = 11.',
      answer: '3x = 11 + 7 = 18, so x = 18 ÷ 3 = 6.',
      keywords: ['solve', 'linear', 'x = 6'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Matrices',
      text: 'What is a null (zero) matrix?',
      answer:
          'A null or zero matrix is a matrix in which every element is zero. '
          'It is usually denoted by O.',
      keywords: ['null matrix', 'zero', 'elements'],
    ),
    BankItem(
      type: QuestionType.long,
      chapter: 'Algebraic Expressions',
      text:
          'Prove the algebraic identity (a + b)² = a² + 2ab + b² and use it to '
          'evaluate (103)².',
      answer: '(a + b)² = (a + b)(a + b) = a² + ab + ba + b² = a² + 2ab + b². '
          'For (103)², take a = 100, b = 3: 100² + 2(100)(3) + 3² = 10000 + '
          '600 + 9 = 10609. Marking: expansion/proof (4), substitution (2), '
          'correct value 10609 (2).',
      keywords: ['identity', 'expansion', '10609', 'proof'],
      difficulty: 'Hard',
    ),
    BankItem(
      type: QuestionType.long,
      chapter: 'Geometry',
      text: 'State and explain the Pythagoras theorem with a labelled example.',
      answer:
          'Pythagoras theorem: in a right-angled triangle, the square of the '
          'hypotenuse equals the sum of the squares of the other two sides '
          '(c² = a² + b²). Example: if a = 3 and b = 4 then c² = 9 + 16 = 25, '
          'so c = 5. Marking: correct statement (3), formula (2), worked '
          'example (3).',
      keywords: ['pythagoras', 'hypotenuse', 'right angle', 'c=5'],
      difficulty: 'Medium',
    ),
  ];

  // ---------------------------- English (9th) ----------------------------
  static const List<BankItem> _english = [
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Grammar',
      text: 'Choose the correct form: "She ___ to school every day."',
      options: ['go', 'goes', 'going', 'gone'],
      correctIndex: 1,
      answer: 'goes',
      keywords: ['subject verb agreement', 'present tense'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Parts of Speech',
      text:
          'In the sentence "The boy ran quickly", the word "quickly" is a(n):',
      options: ['Noun', 'Verb', 'Adverb', 'Adjective'],
      correctIndex: 2,
      answer: 'Adverb',
      keywords: ['adverb', 'parts of speech'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Vocabulary',
      text: 'The antonym of "ancient" is:',
      options: ['Old', 'Modern', 'Historic', 'Past'],
      correctIndex: 1,
      answer: 'Modern',
      keywords: ['antonym', 'opposite', 'modern'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Tenses',
      text: 'Identify the tense: "They have finished their work."',
      options: ['Present Simple', 'Present Perfect', 'Past Simple', 'Future'],
      correctIndex: 1,
      answer: 'Present Perfect',
      keywords: ['present perfect', 'have finished', 'tense'],
      difficulty: 'Medium',
    ),
    BankItem(
      type: QuestionType.mcq,
      chapter: 'Punctuation',
      text: 'Which punctuation mark ends an interrogative sentence?',
      options: ['Full stop', 'Question mark', 'Comma', 'Colon'],
      correctIndex: 1,
      answer: 'Question mark',
      keywords: ['punctuation', 'question mark', 'interrogative'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Parts of Speech',
      text: 'Define a noun and give two examples.',
      answer:
          'A noun is a word used to name a person, place, thing or idea, e.g. '
          '"Ali" (person) and "school" (place).',
      keywords: ['noun', 'name', 'person', 'place', 'example'],
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Tenses',
      text: 'Change into past tense: "He writes a letter."',
      answer: '"He wrote a letter."',
      keywords: ['past tense', 'wrote'],
      difficulty: 'Easy',
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Vocabulary',
      text: 'Use the word "diligent" in a meaningful sentence.',
      answer: 'Example: "The diligent student completed all her assignments on '
          'time." (Any sentence that shows "diligent" means hard-working is '
          'acceptable.)',
      keywords: ['diligent', 'hardworking', 'sentence'],
    ),
    BankItem(
      type: QuestionType.short,
      chapter: 'Grammar',
      text: 'What is the difference between an adjective and an adverb?',
      answer:
          'An adjective modifies (describes) a noun or pronoun, e.g. "a fast '
          'car", while an adverb modifies a verb, adjective or another adverb, '
          'e.g. "he drove fast".',
      keywords: ['adjective', 'adverb', 'noun', 'verb', 'modify'],
    ),
    BankItem(
      type: QuestionType.long,
      chapter: 'Composition',
      text: 'Write a paragraph of about 100 words on "The Importance of '
          'Education".',
      answer:
          'Marking guideline: relevance to the topic (3), correct grammar and '
          'spelling (2), coherent structure with a clear opening and closing '
          '(2), appropriate vocabulary and length (~100 words) (1). Accept any '
          'well-organised paragraph covering ideas such as literacy, '
          'character building, economic progress and national development.',
      keywords: ['education', 'paragraph', 'composition'],
      difficulty: 'Medium',
    ),
    BankItem(
      type: QuestionType.long,
      chapter: 'Letter Writing',
      text: 'Write a letter to your headmaster requesting a few days\' leave.',
      answer:
          'Marking guideline: correct application format — recipient, subject, '
          'salutation, body and closing (3); clear reason for leave and dates '
          '(2); polite tone (2); grammar and neatness (1).',
      keywords: ['letter', 'application', 'leave', 'format'],
      difficulty: 'Medium',
    ),
  ];
}
