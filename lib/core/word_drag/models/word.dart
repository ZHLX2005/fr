class Word {
  final String id;
  final String text;
  final String phonetic;
  final String definition;
  final String example;
  bool mastered;

  Word({
    required this.id,
    required this.text,
    required this.phonetic,
    required this.definition,
    required this.example,
    this.mastered = false,
  });

  static List<Word> sampleWords = [
    Word(
      id: '1',
      text: 'ephemeral',
      phonetic: '/ɪˈfem.ər.əl/',
      definition: 'lasting for a very short time',
      example: 'Fame is ephemeral in the digital age.',
    ),
    Word(
      id: '2',
      text: 'serendipity',
      phonetic: '/ˌser.ənˈdɪp.ə.ti/',
      definition: 'the occurrence of events by chance in a happy way',
      example: 'Finding that book was pure serendipity.',
    ),
    Word(
      id: '3',
      text: 'mellifluous',
      phonetic: '/meˈlɪf.lu.əs/',
      definition: 'sweet or musical; pleasant to hear',
      example: 'Her voice was mellifluous and captivating.',
    ),
  ];
}
