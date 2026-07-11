import 'dart:io';

import 'package:misakid_spacy_en/src/model/model.dart';
import 'package:test/test.dart';

void main() {
  final modelDirectory =
      Platform.environment['MISAKID_SPACY_EN_MODEL_DIR'] ??
      Platform.environment['MISAKI_SPACY_EN_MODEL_DIR'];
  final provisionedSkip = modelDirectory == null
      ? 'Set MISAKID_SPACY_EN_MODEL_DIR to en_core_web_sm-3.8.0.'
      : false;
  late SpacyEnglishTaggerModel model;

  setUpAll(() {
    if (modelDirectory == null) return;
    final parameters = SpacyEnglishSerializedModelLoader.decode(
      tok2vecModel: File('$modelDirectory/tok2vec/model').readAsBytesSync(),
      taggerModel: File('$modelDirectory/tagger/model').readAsBytesSync(),
    );
    model = SpacyEnglishTaggerModel(parameters);
  });

  test('matches pinned spaCy intermediates and tags', () {
    final result = model.infer(_helloWorldFeatures);

    expect(result.tags, const <String>['UH', ',', 'NN', '.']);
    _expectSamples(
      result.projected,
      const <int>[0, 1, 2, 48, 95],
      _projectedSamples,
      0.0001,
    );
    _expectSamples(
      result.encoded,
      const <int>[0, 1, 2, 48, 95],
      _encodedSamples,
      0.0002,
    );
    _expectSamples(
      result.scores,
      const <int>[0, 1, 2, 25, 49],
      _scoreSamples,
      0.001,
    );
  }, skip: provisionedSkip);

  test('matches pinned spaCy tags across context and whitespace tokens', () {
    expect(model.infer(_pangramFeatures).tags, const <String>[
      'DT',
      'JJ',
      'JJ',
      'NN',
      'VBZ',
      'IN',
      'CD',
      'JJ',
      'NNS',
      '.',
    ]);
    expect(model.infer(_whitespaceFeatures).tags, const <String>[
      'CD',
      '_SP',
      'CD',
      '_SP',
      'CD',
      '_SP',
      'CD',
    ]);
  }, skip: provisionedSkip);

  test('returns correctly shaped empty model output', () {
    final result = model.infer(const <SpacyTokenFeatures>[]);
    expect((result.projected.rows, result.projected.columns), (0, 96));
    expect((result.encoded.rows, result.encoded.columns), (0, 96));
    expect((result.scores.rows, result.scores.columns), (0, 50));
    expect(result.tags, isEmpty);
  }, skip: provisionedSkip);
}

void _expectSamples(
  SpacyFloat32Matrix actual,
  List<int> columns,
  List<List<double>> expected,
  double tolerance,
) {
  for (var row = 0; row < expected.length; row++) {
    for (var sample = 0; sample < columns.length; sample++) {
      expect(
        actual.valueAt(row, columns[sample]),
        closeTo(expected[row][sample], tolerance),
        reason: 'row $row, column ${columns[sample]}',
      );
    }
  }
}

const List<SpacyTokenFeatures> _helloWorldFeatures = <SpacyTokenFeatures>[
  SpacyTokenFeatures(
    norm: 5983625672228268878,
    prefix: -9095990006690799107,
    suffix: 7819752793552135697,
    shape: -2374649066819379754,
    spacy: 0,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: 2593208677638477497,
    prefix: 2593208677638477497,
    suffix: 2593208677638477497,
    shape: 2593208677638477497,
    spacy: 1,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: 1703489418272052182,
    prefix: 260667111241363922,
    suffix: 1946122098559876805,
    shape: -5336683462387177326,
    spacy: 0,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: -951941027396968864,
    prefix: -951941027396968864,
    suffix: -951941027396968864,
    shape: -951941027396968864,
    spacy: 0,
    isSpace: 0,
  ),
];

const List<SpacyTokenFeatures> _pangramFeatures = <SpacyTokenFeatures>[
  SpacyTokenFeatures(
    norm: 7425985699627899538,
    prefix: 5582244037879929967,
    suffix: 5059648917813135842,
    shape: -246014574489343830,
    spacy: 1,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: -6004239426076694769,
    prefix: -4372068138184907780,
    suffix: 4162776279516314175,
    shape: -5336683462387177326,
    spacy: 1,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: -2879850288315583423,
    prefix: -2848371626963967819,
    suffix: 2646123857127441627,
    shape: -5336683462387177326,
    spacy: 1,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: 4333436952782779665,
    prefix: -5335983353249293789,
    suffix: 4333436952782779665,
    shape: 4088098365541558500,
    spacy: 1,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: 159845598865486485,
    prefix: 8565857220533584986,
    suffix: 4981378099850271565,
    shape: -5336683462387177326,
    spacy: 1,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: 5456543204961066030,
    prefix: 1489474827855109852,
    suffix: -2243209188662177792,
    shape: -5336683462387177326,
    spacy: 1,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: 6349566914108460152,
    prefix: 5533571732986600803,
    suffix: 6349566914108460152,
    shape: 4620368362210911820,
    spacy: 1,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: 8463806658378306174,
    prefix: 2985121464356781022,
    suffix: 6437086851439729488,
    shape: -5336683462387177326,
    spacy: 1,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: 2242371127287770124,
    prefix: 8148669997605808657,
    suffix: 961703434132517836,
    shape: -5336683462387177326,
    spacy: 0,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: -5800678186108009822,
    prefix: -5800678186108009822,
    suffix: -5800678186108009822,
    shape: -5800678186108009822,
    spacy: 0,
    isSpace: 0,
  ),
];

const List<SpacyTokenFeatures> _whitespaceFeatures = <SpacyTokenFeatures>[
  SpacyTokenFeatures(
    norm: -992628721797871016,
    prefix: -1019419104455454359,
    suffix: -5955644239217876074,
    shape: -246014574489343830,
    spacy: 0,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: 8369835018492280547,
    prefix: 8369835018492280547,
    suffix: 8369835018492280547,
    shape: 8369835018492280547,
    spacy: 0,
    isSpace: 1,
  ),
  SpacyTokenFeatures(
    norm: -6734905781285551264,
    prefix: -3077498904791325916,
    suffix: -6734905781285551264,
    shape: 4088098365541558500,
    spacy: 0,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: 962983613142996970,
    prefix: 962983613142996970,
    suffix: 962983613142996970,
    shape: 962983613142996970,
    spacy: 0,
    isSpace: 1,
  ),
  SpacyTokenFeatures(
    norm: 8241648526530492509,
    prefix: -3077498904791325916,
    suffix: 1885430333798768031,
    shape: -5336683462387177326,
    spacy: 1,
    isSpace: 0,
  ),
  SpacyTokenFeatures(
    norm: 8532415787641010193,
    prefix: 8532415787641010193,
    suffix: 8532415787641010193,
    shape: 8532415787641010193,
    spacy: 0,
    isSpace: 1,
  ),
  SpacyTokenFeatures(
    norm: -5163472758948805104,
    prefix: -5335983353249293789,
    suffix: -869728933464466833,
    shape: -5336683462387177326,
    spacy: 0,
    isSpace: 0,
  ),
];

const List<List<double>> _projectedSamples = <List<double>>[
  <double>[
    0.1736225188,
    -0.1552261710,
    0.2915379405,
    -0.0048513412,
    0.7687033415,
  ],
  <double>[
    -0.3295617700,
    -0.0644964874,
    -0.1127762198,
    0.1336953342,
    -0.1841896176,
  ],
  <double>[
    -0.1045982540,
    -0.1475664377,
    0.2690192461,
    0.0897681564,
    -0.2333863378,
  ],
  <double>[
    -0.0230706334,
    -0.0779134333,
    -0.1127025038,
    0.0917587876,
    -0.1388184130,
  ],
];

const List<List<double>> _encodedSamples = <List<double>>[
  <double>[
    -0.7434543371,
    -0.7547786236,
    -0.0548051298,
    0.2642705441,
    0.8170117140,
  ],
  <double>[
    -0.5076105595,
    -0.4738247991,
    -0.0919778794,
    0.7721427679,
    -0.7672994137,
  ],
  <double>[
    -0.3640606403,
    -0.4660679698,
    0.2394565046,
    0.2023716271,
    0.5045574307,
  ],
  <double>[
    -1.0126124620,
    -0.2333610952,
    -0.9941767454,
    0.7222229242,
    -0.4295362830,
  ],
];

const List<List<double>> _scoreSamples = <List<double>>[
  <double>[
    -2.2611382008,
    -7.1261234283,
    -3.5752644539,
    0.9818924665,
    -3.1534867287,
  ],
  <double>[
    -4.5835013390,
    3.6443850994,
    15.7894287109,
    -1.7719544172,
    -0.6922685504,
  ],
  <double>[
    -5.1312031746,
    -2.9196631908,
    -5.2636051178,
    1.1589274406,
    -4.5481653214,
  ],
  <double>[
    2.2335777283,
    5.6560125351,
    9.3298797607,
    -0.6932318211,
    -0.9617737532,
  ],
];
