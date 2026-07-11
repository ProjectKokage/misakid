import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:misakid/misaki_zh.dart';
import 'package:misakid_chinese/src/pypinyin.dart';
import 'package:test/test.dart';

const _pinyinPathEnvironment = 'MISAKID_CHINESE_PYPINYIN_DICT';
const _phrasesPathEnvironment = 'MISAKID_CHINESE_PYPINYIN_PHRASES';
const _largePinyinPathEnvironment = 'MISAKID_CHINESE_LARGE_PINYIN';

void main() {
  group('PypinyinTone3Provider', () {
    test('parses synthetic resources and exposes immutable values', () async {
      final provider = await _openSynthetic(
        pinyin: <String, Object?>{
          '${'你'.runes.single}': 'nǐ,nì',
          '${'好'.runes.single}': 'hǎo,hào',
          '${'吗'.runes.single}': 'ma,má,mǎ',
        },
        phrases: <String, Object?>{
          '你好': <Object?>[
            <Object?>['nǐ'],
            <Object?>['hǎo'],
          ],
        },
      );

      expect(provider.tone3('你好'), <String>['ni3', 'hao3']);
      expect(provider.tone3('吗'), <String>['ma5']);
      expect(provider.info.name, 'pypinyin');
      expect(provider.info.version, '0.53.0');
      expect(provider.info.details['pinyinDictRecordCount'], '3');
      expect(provider.info.details['phrasesDictRecordCount'], '1');
      expect(
        () => provider.info.details['mutable'] = 'no',
        throwsUnsupportedError,
      );
      expect(() => provider.tone3('你').add('no'), throwsUnsupportedError);
    });

    test('matches strict mmseg prefix behavior and polyphones', () async {
      final provider = await _openSynthetic(
        pinyin: <String, Object?>{
          '${'一'.runes.single}': 'yī,yí,yì',
          '${'百'.runes.single}': 'bǎi',
          '${'二'.runes.single}': 'èr',
          '${'十'.runes.single}': 'shí',
          '${'三'.runes.single}': 'sān',
          '${'八'.runes.single}': 'bā',
          '${'银'.runes.single}': 'yín',
          '${'行'.runes.single}': 'xíng,háng',
          '${'长'.runes.single}': 'zhǎng,cháng',
          '${'重'.runes.single}': 'zhòng,chóng',
          '${'庆'.runes.single}': 'qìng',
          '${'音'.runes.single}': 'yīn',
          '${'乐'.runes.single}': 'lè,yuè',
        },
        phrases: <String, Object?>{
          '一百': <Object?>[
            <Object?>['yì'],
            <Object?>['bǎi'],
          ],
          // This makes 一百二十 a non-phrase prefix in the same way as the
          // pinned full dictionary.
          '一百二十一': <Object?>[
            <Object?>['yī'],
            <Object?>['bǎi'],
            <Object?>['èr'],
            <Object?>['shí'],
            <Object?>['yī'],
          ],
          '行行': <Object?>[
            <Object?>['xíng'],
            <Object?>['xíng'],
          ],
          '重庆': <Object?>[
            <Object?>['chóng'],
            <Object?>['qìng'],
          ],
          '音乐': <Object?>[
            <Object?>['yīn'],
            <Object?>['yuè'],
          ],
        },
      );

      expect(provider.tone3('一百二十'), <String>['yi1', 'bai3', 'er4', 'shi2']);
      expect(provider.tone3('一百三十八'), <String>[
        'yi4',
        'bai3',
        'san1',
        'shi2',
        'ba1',
      ]);
      expect(provider.tone3('银行行长'), <String>[
        'yin2',
        'xing2',
        'xing2',
        'zhang3',
      ]);
      expect(provider.tone3('重庆'), <String>['chong2', 'qing4']);
      expect(provider.tone3('音乐'), <String>['yin1', 'yue4']);
    });

    test('converts the complete pypinyin tone-symbol table', () async {
      const values = <String>[
        'ā',
        'á',
        'ǎ',
        'à',
        'ē',
        'é',
        'ě',
        'è',
        'ō',
        'ó',
        'ǒ',
        'ò',
        'ī',
        'í',
        'ǐ',
        'ì',
        'ū',
        'ú',
        'ǔ',
        'ù',
        'ǖ',
        'ǘ',
        'ǚ',
        'ǜ',
        'ń',
        'ň',
        'ǹ',
        'm̄',
        'ḿ',
        'm̀',
        'ê̄',
        'ế',
        'ê̌',
        'ề',
      ];
      const expected = <String>[
        'a1',
        'a2',
        'a3',
        'a4',
        'e1',
        'e2',
        'e3',
        'e4',
        'o1',
        'o2',
        'o3',
        'o4',
        'i1',
        'i2',
        'i3',
        'i4',
        'u1',
        'u2',
        'u3',
        'u4',
        'v1',
        'v2',
        'v3',
        'v4',
        'n2',
        'n3',
        'n4',
        'm1',
        'm2',
        'm4',
        'ê1',
        'ê2',
        'ê3',
        'ê4',
      ];
      final pinyin = <String, Object?>{};
      final input = StringBuffer();
      for (var index = 0; index < values.length; index++) {
        final scalar = 0x4e00 + index;
        pinyin['$scalar'] = values[index];
        input.writeCharCode(scalar);
      }
      final provider = await _openSynthetic(
        pinyin: pinyin,
        phrases: _dummyPhrase,
      );

      expect(provider.tone3(input.toString()), expected);
    });

    test('preserves non-Han runs and marks unknown Han as neutral', () async {
      final provider = await _openSynthetic(
        pinyin: <String, Object?>{
          '${'中'.runes.single}': 'zhōng,zhòng',
          '${'国'.runes.single}': 'guó',
        },
        phrases: <String, Object?>{
          '中国': <Object?>[
            <Object?>['zhōng'],
            <Object?>['guó'],
          ],
        },
      );

      expect(provider.tone3('中A?!国'), <String>['zhong1', 'A?!', 'guo2']);
      expect(provider.tone3('A?!'), <String>['A?!']);
      expect(provider.tone3('鿿'), <String>['鿿5']);
      expect(provider.tone3(''), isEmpty);
    });

    test('rejects missing, relative, directory, and linked paths', () async {
      await expectLater(
        PypinyinTone3Provider.open(
          pinyinDictionaryPath: _absolutePath('missing-pinyin'),
          phrasesDictionaryPath: _absolutePath('missing-phrases'),
        ),
        throwsA(isA<BackendUnavailableException>()),
      );
      await expectLater(
        PypinyinTone3Provider.open(
          pinyinDictionaryPath: 'relative.json',
          phrasesDictionaryPath: _absolutePath('missing-phrases'),
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );

      final resources = await _writeResources(
        pinyin: <String, Object?>{'${'你'.runes.single}': 'nǐ'},
        phrases: _dummyPhrase,
      );
      await expectLater(
        _openWithManifest(
          pinyinPath: resources.directory.path,
          pinyinManifest: resources.pinyin,
          phrasesManifest: resources.phrases,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );

      if (!Platform.isWindows) {
        final link = Link(
          '${resources.directory.path}${Platform.pathSeparator}linked',
        );
        await link.create(resources.pinyin.file.path);
        await expectLater(
          _openWithManifest(
            pinyinPath: link.path,
            pinyinManifest: resources.pinyin,
            phrasesManifest: resources.phrases,
          ),
          throwsA(isA<InvalidConfigurationException>()),
        );
      }
    });

    test('rejects checksum, UTF-8, JSON, and schema failures', () async {
      final resources = await _writeResources(
        pinyin: <String, Object?>{'${'你'.runes.single}': 'nǐ'},
        phrases: _dummyPhrase,
      );
      await expectLater(
        openPypinyinTone3ForTesting(
          pinyinDictionaryPath: resources.pinyin.file.path,
          phrasesDictionaryPath: resources.phrases.file.path,
          expectedPinyinSizeBytes: resources.pinyin.bytes.length,
          expectedPinyinSha256: '0' * 64,
          expectedPinyinRecordCount: 1,
          expectedPhrasesSizeBytes: resources.phrases.bytes.length,
          expectedPhrasesSha256: resources.phrases.sha256,
          expectedPhrasesRecordCount: 1,
        ),
        throwsA(isA<MalformedDataException>()),
      );

      for (final badPinyin in <List<int>>[
        <int>[0xff],
        utf8.encode('{'),
        utf8.encode(jsonEncode(<String, Object?>{'bad-key': 'nǐ'})),
        utf8.encode(
          jsonEncode(<String, Object?>{
            '20320': <Object?>['nǐ'],
          }),
        ),
      ]) {
        final bad = await _writeRawResources(
          pinyinBytes: badPinyin,
          phrasesBytes: resources.phrases.bytes,
        );
        await expectLater(
          _openWithManifest(
            pinyinPath: bad.pinyin.file.path,
            pinyinManifest: bad.pinyin,
            phrasesManifest: bad.phrases,
          ),
          throwsA(isA<MalformedDataException>()),
        );
      }

      final malformedPhrase = await _writeResources(
        pinyin: <String, Object?>{'${'你'.runes.single}': 'nǐ'},
        phrases: <String, Object?>{
          '你好': <Object?>[
            <Object?>['nǐ'],
          ],
        },
      );
      await expectLater(
        _openWithManifest(
          pinyinPath: malformedPhrase.pinyin.file.path,
          pinyinManifest: malformedPhrase.pinyin,
          phrasesManifest: malformedPhrase.phrases,
        ),
        throwsA(isA<MalformedDataException>()),
      );
    });

    test('bounds and validates manifests and input Unicode', () async {
      final resources = await _writeResources(
        pinyin: <String, Object?>{'${'你'.runes.single}': 'nǐ'},
        phrases: _dummyPhrase,
      );
      expect(
        () => openPypinyinTone3ForTesting(
          pinyinDictionaryPath: resources.pinyin.file.path,
          phrasesDictionaryPath: resources.phrases.file.path,
          expectedPinyinSizeBytes: 0,
          expectedPinyinSha256: resources.pinyin.sha256,
          expectedPinyinRecordCount: 1,
          expectedPhrasesSizeBytes: resources.phrases.bytes.length,
          expectedPhrasesSha256: resources.phrases.sha256,
          expectedPhrasesRecordCount: 1,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
      final provider = await _openWithManifest(
        pinyinPath: resources.pinyin.file.path,
        pinyinManifest: resources.pinyin,
        phrasesManifest: resources.phrases,
      );
      expect(
        () => provider.tone3(String.fromCharCode(0xd800)),
        throwsA(isA<InvalidConfigurationException>()),
      );
      expect(
        () => provider.tone3('你' * (maximumPypinyinTone3InputScalars + 1)),
        throwsA(isA<InvalidConfigurationException>()),
      );
    });

    test(
      'frontend 1.1 applies large and custom dictionaries in order',
      () async {
        final provider = await _openSyntheticFrontend11(
          pinyin: <String, Object?>{
            '${'女'.runes.single}': 'nǚ,nǜ',
            '${'嗯'.runes.single}': 'ń,ńg,ňg,ǹg,ň,ǹ',
            '${'地'.runes.single}': 'dì,dí',
          },
          phrases: _dummyPhrase,
          largeText:
              '# version: synthetic\n'
              '看不懂: kàn bu dǒng\n'
              '奶奶: nǎi nai\n'
              '音乐: yīn yuè\n'
              '朝阳: zhāo yáng\n'
              '朝阳: cháo yáng\n'
              '行号: xíng hào\n'
              '各地: gè de\n',
        );

        expect(provider.initials('看不懂'), <String>['k', 'b', 'd']);
        expect(provider.finalsTone3('看不懂'), <String>['an4', 'u5', 'ong3']);
        expect(provider.finalsTone3('奶奶'), <String>['ai3', 'ai5']);
        expect(provider.finalsTone3('音乐'), <String>['in1', 've4']);
        expect(provider.tone3('朝阳'), <String>['zhao1', 'yang2']);
        expect(provider.initials('女嗯鿿'), <String>['n', '', '']);
        expect(provider.finalsTone3('女嗯鿿'), <String>['v3', '', '']);

        // The 16 Misaki overrides replace large_pinyin entries.
        expect(provider.finalsTone3('行号'), <String>['ang2', 'ao4']);
        expect(provider.finalsTone3('各地'), <String>['e4', 'i4']);
        expect(provider.finalsTone3('开户行'), <String>['ai1', 'u4', 'ang2']);
        expect(provider.finalsTone3('掺和'), <String>['an1', 'uo5']);
        expect(provider.finalsTone3('呗'), <String>['ei5']);
        // The final single-character load makes de the first 地 reading.
        expect(provider.initials('地'), <String>['d']);
        expect(provider.finalsTone3('地'), <String>['e5']);

        expect(provider.info.details['mode'], 'misaki-chinese-frontend-1.1');
        expect(provider.info.details['largePinyinRecordCount'], '7');
        expect(provider.info.details['largePinyinPhraseCount'], '6');
        expect(provider.info.details['customPhraseOverrideCount'], '16');
      },
    );

    test('frontend strict finals restore standard contracted forms', () async {
      final values = <String, String>{
        '牛': 'niú',
        '归': 'guī',
        '轮': 'lún',
        '元': 'yuán',
        '温': 'wēn',
        '居': 'jū',
        '哟': 'yo',
      };
      final provider = await _openSyntheticFrontend11(
        pinyin: <String, Object?>{
          for (final entry in values.entries)
            '${entry.key.runes.single}': entry.value,
        },
        phrases: _dummyPhrase,
        largeText: '朝阳: zhāo yáng\n',
      );

      expect(provider.initials(values.keys.join()), <String>[
        'n',
        'g',
        'l',
        '',
        '',
        'j',
        '',
      ]);
      expect(provider.finalsTone3(values.keys.join()), <String>[
        'iou2',
        'uei1',
        'uen2',
        'van2',
        'uen1',
        'v1',
        'o5',
      ]);
      expect(provider.finalsTone3('.'), <String>['.']);
    });

    test(
      'frontend large dictionary rejects malformed source records',
      () async {
        for (final largeText in <String>[
          'missing delimiter\n',
          '中国: zhōng\n',
          'ASCII: a s c i i\n',
          '中国: zhōng guó: extra\n',
        ]) {
          await expectLater(
            _openSyntheticFrontend11(
              pinyin: <String, Object?>{'${'你'.runes.single}': 'nǐ'},
              phrases: _dummyPhrase,
              largeText: largeText,
            ),
            throwsA(isA<MalformedDataException>()),
          );
        }
      },
    );

    final pinyinPath = Platform.environment[_pinyinPathEnvironment];
    final phrasesPath = Platform.environment[_phrasesPathEnvironment];
    final provisioned = pinyinPath != null && phrasesPath != null;
    test(
      'matches all pypinyin calls captured by the legacy Misaki oracle',
      () async {
        final provider = await PypinyinTone3Provider.open(
          pinyinDictionaryPath: pinyinPath!,
          phrasesDictionaryPath: phrasesPath!,
        );

        expect(
          provider.info.details,
          containsPair('pinyinDictSizeBytes', '783823'),
        );
        expect(
          provider.info.details,
          containsPair('phrasesDictSizeBytes', '2544982'),
        );
        expect(_auditExpectations, hasLength(60));
        for (final entry in _auditExpectations.entries) {
          expect(
            provider.tone3(entry.key),
            entry.value,
            reason: 'pypinyin tone3 mismatch for `${entry.key}`',
          );
        }
        expect(provider.tone3('女'), <String>['nv3']);
        expect(provider.tone3('中A国'), <String>['zhong1', 'A', 'guo2']);
      },
      skip: provisioned
          ? false
          : 'Set $_pinyinPathEnvironment and $_phrasesPathEnvironment to the pinned pypinyin 0.53.0 JSON files.',
    );

    final largePinyinPath = Platform.environment[_largePinyinPathEnvironment];
    final frontendProvisioned = provisioned && largePinyinPath != null;
    test(
      'matches all pypinyin calls captured by the frontend-1.1 oracle',
      () async {
        final provider = await PypinyinTone3Provider.openFrontend11(
          pinyinDictionaryPath: pinyinPath!,
          phrasesDictionaryPath: phrasesPath!,
          largePinyinDictionaryPath: largePinyinPath!,
        );
        expect(_frontendInitialExpectations, hasLength(79));
        expect(_frontendFinalExpectations, hasLength(83));
        for (final entry in _frontendInitialExpectations.entries) {
          expect(
            provider.initials(entry.key),
            entry.value,
            reason: 'pypinyin initials mismatch for `${entry.key}`',
          );
        }
        for (final entry in _frontendFinalExpectations.entries) {
          expect(
            provider.finalsTone3(entry.key),
            entry.value,
            reason: 'pypinyin finals-tone3 mismatch for `${entry.key}`',
          );
        }
        const direct = <String, List<List<String>>>{
          '地': <List<String>>[
            <String>['d'],
            <String>['e5'],
          ],
          '各地': <List<String>>[
            <String>['g', 'd'],
            <String>['e4', 'i4'],
          ],
          '为准': <List<String>>[
            <String>['', 'zh'],
            <String>['uei2', 'uen3'],
          ],
          '借还款': <List<String>>[
            <String>['j', 'h', 'k'],
            <String>['ie4', 'uan2', 'uan3'],
          ],
          '时间为': <List<String>>[
            <String>['sh', 'j', ''],
            <String>['i2', 'ian1', 'uei2'],
          ],
          '色差': <List<String>>[
            <String>['s', 'ch'],
            <String>['e4', 'a1'],
          ],
          '咗': <List<String>>[
            <String>['z'],
            <String>['uo5'],
          ],
          '嘞': <List<String>>[
            <String>['l'],
            <String>['ei5'],
          ],
          '放款行': <List<String>>[
            <String>['f', 'k', 'h'],
            <String>['ang4', 'uan3', 'ang2'],
          ],
          '茧行': <List<String>>[
            <String>['j', 'h'],
            <String>['ian3', 'ang2'],
          ],
        };
        for (final entry in direct.entries) {
          expect(provider.initials(entry.key), entry.value[0]);
          expect(provider.finalsTone3(entry.key), entry.value[1]);
        }
        expect(provider.info.details['largePinyinRecordCount'], '411959');
        expect(provider.info.details['largePinyinPhraseCount'], '411957');
      },
      skip: frontendProvisioned
          ? false
          : 'Also set $_largePinyinPathEnvironment to the pinned pypinyin-dict 0.9.0 large_pinyin.txt file.',
    );
  });
}

const Map<String, Object?> _dummyPhrase = <String, Object?>{
  '你好': <Object?>[
    <Object?>['nǐ'],
    <Object?>['hǎo'],
  ],
};

Future<PypinyinTone3Provider> _openSynthetic({
  required Map<String, Object?> pinyin,
  required Map<String, Object?> phrases,
}) async {
  final resources = await _writeResources(pinyin: pinyin, phrases: phrases);
  return _openWithManifest(
    pinyinPath: resources.pinyin.file.path,
    pinyinManifest: resources.pinyin,
    phrasesManifest: resources.phrases,
  );
}

Future<PypinyinTone3Provider> _openSyntheticFrontend11({
  required Map<String, Object?> pinyin,
  required Map<String, Object?> phrases,
  required String largeText,
}) async {
  final resources = await _writeResources(pinyin: pinyin, phrases: phrases);
  final largeBytes = utf8.encode(largeText);
  final largeFile = File(
    '${resources.directory.path}${Platform.pathSeparator}large_pinyin.txt',
  );
  await largeFile.writeAsBytes(largeBytes, flush: true);
  final records = const LineSplitter()
      .convert(largeText)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList(growable: false);
  final phrasesInLarge = <String>{
    for (final record in records)
      record.contains(':') ? record.split(':').first.trim() : record,
  };
  return openPypinyinFrontend11ForTesting(
    pinyinDictionaryPath: resources.pinyin.file.path,
    phrasesDictionaryPath: resources.phrases.file.path,
    largePinyinDictionaryPath: largeFile.path,
    expectedPinyinSizeBytes: resources.pinyin.bytes.length,
    expectedPinyinSha256: resources.pinyin.sha256,
    expectedPinyinRecordCount: resources.pinyin.recordCount,
    expectedPhrasesSizeBytes: resources.phrases.bytes.length,
    expectedPhrasesSha256: resources.phrases.sha256,
    expectedPhrasesRecordCount: resources.phrases.recordCount,
    expectedLargePinyinSizeBytes: largeBytes.length,
    expectedLargePinyinSha256: crypto.sha256.convert(largeBytes).toString(),
    expectedLargePinyinRecordCount: records.length,
    expectedLargePinyinPhraseCount: phrasesInLarge.length,
  );
}

Future<PypinyinTone3Provider> _openWithManifest({
  required String pinyinPath,
  required _FixtureResource pinyinManifest,
  required _FixtureResource phrasesManifest,
}) => openPypinyinTone3ForTesting(
  pinyinDictionaryPath: pinyinPath,
  phrasesDictionaryPath: phrasesManifest.file.path,
  expectedPinyinSizeBytes: pinyinManifest.bytes.length,
  expectedPinyinSha256: pinyinManifest.sha256,
  expectedPinyinRecordCount: pinyinManifest.recordCount,
  expectedPhrasesSizeBytes: phrasesManifest.bytes.length,
  expectedPhrasesSha256: phrasesManifest.sha256,
  expectedPhrasesRecordCount: phrasesManifest.recordCount,
);

Future<_FixtureResources> _writeResources({
  required Map<String, Object?> pinyin,
  required Map<String, Object?> phrases,
}) => _writeRawResources(
  pinyinBytes: utf8.encode(jsonEncode(pinyin)),
  phrasesBytes: utf8.encode(jsonEncode(phrases)),
);

Future<_FixtureResources> _writeRawResources({
  required List<int> pinyinBytes,
  required List<int> phrasesBytes,
}) async {
  final directory = await Directory.systemTemp.createTemp('misakid-pypinyin-');
  addTearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  final pinyinFile = File(
    '${directory.path}${Platform.pathSeparator}pinyin_dict.json',
  );
  final phrasesFile = File(
    '${directory.path}${Platform.pathSeparator}phrases_dict.json',
  );
  await pinyinFile.writeAsBytes(pinyinBytes, flush: true);
  await phrasesFile.writeAsBytes(phrasesBytes, flush: true);
  return _FixtureResources(
    directory,
    _FixtureResource(pinyinFile, pinyinBytes),
    _FixtureResource(phrasesFile, phrasesBytes),
  );
}

String _absolutePath(String suffix) => Platform.isWindows
    ? 'C:\\definitely-missing\\$suffix'
    : '/definitely-missing/$suffix';

final class _FixtureResources {
  const _FixtureResources(this.directory, this.pinyin, this.phrases);

  final Directory directory;
  final _FixtureResource pinyin;
  final _FixtureResource phrases;
}

final class _FixtureResource {
  _FixtureResource(this.file, List<int> bytes)
    : bytes = List<int>.unmodifiable(bytes),
      sha256 = crypto.sha256.convert(bytes).toString(),
      recordCount = _recordCount(bytes);

  final File file;
  final List<int> bytes;
  final String sha256;
  final int recordCount;

  static int _recordCount(List<int> bytes) {
    try {
      final value = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      return value is Map<String, Object?> ? value.length : 1;
    } on FormatException {
      return 1;
    }
  }
}

const Map<String, List<String>> _auditExpectations = <String, List<String>>{
  '一': <String>['yi1'],
  '一十三万': <String>['yi1', 'shi2', 'san1', 'wan4'],
  '一百三十八': <String>['yi4', 'bai3', 'san1', 'shi2', 'ba1'],
  '一百二十': <String>['yi1', 'bai3', 'er4', 'shi2'],
  '七月': <String>['qi1', 'yue4'],
  '三': <String>['san1'],
  '三十': <String>['san1', 'shi2'],
  '三点': <String>['san1', 'dian3'],
  '与': <String>['yu3'],
  '世界': <String>['shi4', 'jie4'],
  '中文': <String>['zhong1', 'wen2'],
  '二': <String>['er4'],
  '二十九': <String>['er4', 'shi2', 'jiu3'],
  '二十四': <String>['er4', 'shi2', 'si4'],
  '二千': <String>['er4', 'qian1'],
  '二点五': <String>['er4', 'dian3', 'wu3'],
  '二零二': <String>['er4', 'ling2', 'er4'],
  '五': <String>['wu3'],
  '亿零': <String>['yi4', 'ling2'],
  '今天': <String>['jin1', 'tian1'],
  '价格': <String>['jia4', 'ge2'],
  '你': <String>['ni3'],
  '你好': <String>['ni3', 'hao3'],
  '元': <String>['yuan2'],
  '八': <String>['ba1'],
  '八千': <String>['ba1', 'qian1'],
  '六年': <String>['liu4', 'nian2'],
  '再见': <String>['zai4', 'jian4'],
  '十日': <String>['shi2', 'ri4'],
  '吗': <String>['ma5'],
  '和': <String>['he2'],
  '四五': <String>['si4', 'wu3'],
  '四分之三': <String>['si4', 'fen1', 'zhi1', 'san1'],
  '四十五': <String>['si4', 'shi2', 'wu3'],
  '增长': <String>['zeng1', 'zhang3'],
  '好': <String>['hao3'],
  '妈妈': <String>['ma1', 'ma1'],
  '快乐': <String>['kuai4', 'le4'],
  '是': <String>['shi4'],
  '朋友': <String>['peng2', 'you3'],
  '比例': <String>['bi3', 'li4'],
  '测试': <String>['ce4', 'shi4'],
  '灣': <String>['wan1'],
  '电话': <String>['dian4', 'hua4'],
  '百分之十': <String>['bai3', 'fen1', 'zhi1', 'shi2'],
  '禰': <String>['mi2'],
  '繁體': <String>['fan2', 'ti3'],
  '臺': <String>['tai2'],
  '與': <String>['yu3'],
  '负二负': <String>['fu4', 'er4', 'fu4'],
  '重庆': <String>['chong2', 'qing4'],
  '银行行长': <String>['yin2', 'xing2', 'xing2', 'zhang3'],
  '零': <String>['ling2'],
  '靐': <String>['bing4'],
  '音乐': <String>['yin1', 'yue4'],
  '马': <String>['ma3'],
  '骂': <String>['ma4'],
  '齉': <String>['nang4'],
  '龘': <String>['da2'],
  '鿿': <String>['鿿5'],
};

const Map<String, List<String>> _frontendInitialExpectations =
    <String, List<String>>{
      '一十三万': <String>['', 'sh', 's', ''],
      '一天': <String>['', 't'],
      '一段': <String>['', 'd'],
      '一百三十八': <String>['', 'b', 's', 'sh', 'b'],
      '一百二十': <String>['', 'b', '', 'sh'],
      '七月': <String>['q', ''],
      '三': <String>['s'],
      '三十': <String>['s', 'sh'],
      '三点': <String>['s', 'd'],
      '不对': <String>['b', 'd'],
      '不怕': <String>['b', 'p'],
      '世界': <String>['sh', 'j'],
      '中文': <String>['zh', ''],
      '二十九': <String>['', 'sh', 'j'],
      '二十四': <String>['', 'sh', 's'],
      '二千': <String>['', 'q'],
      '二点五': <String>['', 'd', ''],
      '二零二': <String>['', 'l', ''],
      '亿零': <String>['', 'l'],
      '什么': <String>['sh', 'm'],
      '今天': <String>['j', 't'],
      '价格': <String>['j', 'g'],
      '你': <String>['n'],
      '你好': <String>['n', 'h'],
      '你好很': <String>['n', 'h', 'h'],
      '元': <String>[''],
      '八': <String>['b'],
      '八千': <String>['b', 'q'],
      '六年': <String>['l', 'n'],
      '再见': <String>['z', 'j'],
      '十日': <String>['sh', 'r'],
      '发卡行': <String>['f', 'k', 'h'],
      '听一听': <String>['t', '', 't'],
      '呗': <String>['b'],
      '嗯': <String>[''],
      '嗲': <String>['d'],
      '四五': <String>['s', ''],
      '四十五': <String>['s', 'sh', ''],
      '增长': <String>['z', 'zh'],
      '女儿': <String>['n', ''],
      '奶奶': <String>['n', 'n'],
      '好': <String>['h'],
      '妈妈': <String>['m', 'm'],
      '小院儿': <String>['x', '', ''],
      '少儿': <String>['sh', ''],
      '开户行': <String>['k', 'h', 'h'],
      '掺和': <String>['ch', 'h'],
      '是': <String>['sh'],
      '桌子': <String>['zh', 'z'],
      '汉字': <String>['h', 'z'],
      '测试': <String>['c', 'sh'],
      '灣': <String>[''],
      '电话': <String>['d', 'h'],
      '百分之十': <String>['b', 'f', 'zh', 'sh'],
      '看一看': <String>['k', '', 'k'],
      '看不懂': <String>['k', 'b', 'd'],
      '看看': <String>['k', 'k'],
      '禰': <String>['m'],
      '第一名': <String>['d', '', 'm'],
      '繁體': <String>['f', 't'],
      '纸老虎': <String>['zh', 'l', 'h'],
      '胡同儿': <String>['h', 't', ''],
      '臺': <String>['t'],
      '與': <String>[''],
      '花儿': <String>['h', ''],
      '范儿': <String>['f', ''],
      '蒙古包': <String>['m', 'g', 'b'],
      '行号': <String>['h', 'h'],
      '衣服': <String>['', 'f'],
      '试试': <String>['sh', 'sh'],
      '负': <String>['f'],
      '负二': <String>['f', ''],
      '重庆': <String>['ch', 'q'],
      '零': <String>['l'],
      '靐': <String>['b'],
      '音乐': <String>['', ''],
      '齉': <String>['n'],
      '龘': <String>['d'],
      '鿿': <String>[''],
    };

const Map<String, List<String>> _frontendFinalExpectations =
    <String, List<String>>{
      '.': <String>['.'],
      '一十三万': <String>['i1', 'i2', 'an1', 'uan4'],
      '一天': <String>['i4', 'ian1'],
      '一段': <String>['i1', 'uan4'],
      '一百三十八': <String>['i4', 'ai3', 'an1', 'i2', 'a1'],
      '一百二十': <String>['i1', 'ai3', 'er4', 'i2'],
      '七月': <String>['i1', 've4'],
      '三': <String>['an1'],
      '三十': <String>['an1', 'i2'],
      '三点': <String>['an1', 'ian3'],
      '不对': <String>['u2', 'uei4'],
      '不怕': <String>['u4', 'a4'],
      '世界': <String>['i4', 'ie4'],
      '中文': <String>['ong1', 'uen2'],
      '二十九': <String>['er4', 'i2', 'iou3'],
      '二十四': <String>['er4', 'i2', 'i4'],
      '二千': <String>['er4', 'ian1'],
      '二点五': <String>['er4', 'ian3', 'u3'],
      '二零二': <String>['er4', 'ing2', 'er4'],
      '亿零': <String>['i4', 'ing2'],
      '什么': <String>['en2', 'e5'],
      '今天': <String>['in1', 'ian1'],
      '价格': <String>['ia4', 'e2'],
      '你': <String>['i3'],
      '你好': <String>['i3', 'ao3'],
      '你好很': <String>['i3', 'ao3', 'en3'],
      '儿': <String>['er2'],
      '元': <String>['van2'],
      '八': <String>['a1'],
      '八千': <String>['a1', 'ian1'],
      '六年': <String>['iou4', 'ian2'],
      '再见': <String>['ai4', 'ian4'],
      '十日': <String>['i2', 'i4'],
      '发卡行': <String>['a4', 'a3', 'ang2'],
      '听一听': <String>['ing1', 'i1', 'ing1'],
      '呗': <String>['ei5'],
      '嗯': <String>[''],
      '嗲': <String>['ia3'],
      '四五': <String>['i4', 'u3'],
      '四十五': <String>['i4', 'i2', 'u3'],
      '增长': <String>['eng1', 'ang3'],
      '女儿': <String>['v3', 'er2'],
      '奶奶': <String>['ai3', 'ai5'],
      '好': <String>['ao3'],
      '妈妈': <String>['a1', 'a5'],
      '小院儿': <String>['iao3', 'van4', 'er5'],
      '少儿': <String>['ao4', 'er2'],
      '开户行': <String>['ai1', 'u4', 'ang2'],
      '很': <String>['en3'],
      '掺和': <String>['an1', 'uo5'],
      '是': <String>['i4'],
      '桌子': <String>['uo1', 'i5'],
      '汉字': <String>['an4', 'i4'],
      '测试': <String>['e4', 'i4'],
      '灣': <String>['uan1'],
      '电话': <String>['ian4', 'ua4'],
      '百分之十': <String>['ai3', 'en1', 'i1', 'i2'],
      '看一看': <String>['an4', 'i1', 'an4'],
      '看不懂': <String>['an4', 'u5', 'ong3'],
      '看看': <String>['an4', 'an4'],
      '禰': <String>['i2'],
      '第一名': <String>['i4', 'i4', 'ing2'],
      '繁體': <String>['an2', 'i3'],
      '纸老虎': <String>['i3', 'ao3', 'u3'],
      '胡同': <String>['u2', 'ong4'],
      '胡同儿': <String>['u2', 'ong4', 'er2'],
      '臺': <String>['ai2'],
      '與': <String>['v3'],
      '花儿': <String>['ua1', 'er2'],
      '范儿': <String>['an4', 'er2'],
      '蒙古包': <String>['eng3', 'u3', 'ao1'],
      '行号': <String>['ang2', 'ao4'],
      '衣服': <String>['i1', 'u2'],
      '试试': <String>['i4', 'i4'],
      '负': <String>['u4'],
      '负二': <String>['u4', 'er4'],
      '重庆': <String>['ong2', 'ing4'],
      '零': <String>['ing2'],
      '靐': <String>['ing4'],
      '音乐': <String>['in1', 've4'],
      '齉': <String>['ang4'],
      '龘': <String>['a2'],
      '鿿': <String>[''],
    };
