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
    Word(
      id: '4',
      text: 'ubiquitous',
      phonetic: '/juːˈbɪk.wɪ.təs/',
      definition: 'present, appearing, or found everywhere',
      example: 'Smartphones have become ubiquitous in modern society.',
    ),
    Word(
      id: '5',
      text: 'eloquent',
      phonetic: '/ˈel.ə.kwənt/',
      definition: 'fluent or persuasive in speaking or writing',
      example: 'The lawyer gave an eloquent closing argument.',
    ),
    Word(
      id: '6',
      text: 'resilient',
      phonetic: '/rɪˈzɪl.i.ənt/',
      definition: 'able to recover quickly from difficulties',
      example: 'Children are often more resilient than adults expect.',
    ),
    Word(
      id: '7',
      text: 'pragmatic',
      phonetic: '/præɡˈmæt.ɪk/',
      definition: 'dealing with things sensibly and realistically',
      example: 'We need a pragmatic approach to solve this problem.',
    ),
    Word(
      id: '8',
      text: 'meticulous',
      phonetic: '/məˈtɪk.jə.ləs/',
      definition: 'showing great attention to detail; very careful',
      example: 'She was meticulous in her research methodology.',
    ),
    Word(
      id: '9',
      text: 'inevitable',
      phonetic: '/ɪnˈev.ɪ.tə.bəl/',
      definition: 'certain to happen; unavoidable',
      example: 'Change is inevitable in any growing organization.',
    ),
    Word(
      id: '10',
      text: 'tenacious',
      phonetic: '/təˈneɪ.ʃəs/',
      definition: 'holding firmly to something; persistent',
      example: 'Her tenacious spirit helped her overcome many obstacles.',
    ),
  ];
}
