import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:misakid_mecab_ja/misakid_mecab_ja.dart';

const _resourceBaseUrl = String.fromEnvironment(
  'MISAKID_TEST_RESOURCE_BASE_URL',
);
const _resourceToken = String.fromEnvironment('MISAKID_TEST_RESOURCE_TOKEN');
const _fixtureSha256 =
    'c599ac58455263a9c9e100f175e9eaa07d1b9e77194a075dea6d02d3a1627a48';
const _dictionaryTreeSha256 =
    '95bd65fa96955b644c15510932ca8439f463ac8b66f57bac6dfee5e29fa03115';
const _wordListSha256 =
    'a93a8e8aee24db307a32becb8bf01c4c2908ecf37e6c91f7a705fafdfeba67ff';
const _upstreamCommit = 'fba1236595f2d2bf21d414ba6e57d25256afada3';

const _dictionaryPaths = <String>{
  'README',
  'char.bin',
  'char.def',
  'dicrc',
  'feature.def',
  'left-id.def',
  'licenses/AUTHORS',
  'licenses/BSD',
  'licenses/COPYING',
  'licenses/GPL',
  'licenses/LGPL',
  'matrix.bin',
  'mecabrc',
  'model.bin',
  'rewrite.def',
  'right-id.def',
  'sys.dic',
  'unk.def',
  'unk.dic',
  'version',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'bundled Japanese backend matches all pinned Cutlet fixtures',
    (_) async {
      final provisioner = _LoopbackProvisioner.fromEnvironment();
      _ProvisionedResources? resources;
      MecabJapaneseCutletBackend? backend;
      Uint8List? wordListBytes;
      try {
        final provisioned = await provisioner.provision();
        resources = provisioned;
        final fixtures = await _readFixtures(provisioned.fixture);
        _expectFixtureContract(fixtures);

        wordListBytes = await provisioned.wordList.readAsBytes();
        backend = await MecabJapaneseCutletBackend.openBundled(
          dictionaryPath: provisioned.dictionary.path,
          wordListBytes: wordListBytes,
        );
        wordListBytes.fillRange(0, wordListBytes.length, 0);

        expect(backend.info.name, 'mecab-unidic-cutlet');
        expect(backend.info.version, '0.996/unidic-3.1.0');
        expect(
          backend.info.details['platform'],
          'native-assets-${Abi.current()}',
        );
        expect(
          backend.info.details['nativeBuildProfile'],
          'misakid-mecab-ja-build-v2-portable',
        );
        expect(
          backend.info.details['dictionaryTreeSha256'],
          _dictionaryTreeSha256,
        );
        expect(backend.info.details['wordMembershipVersion'], _upstreamCommit);

        var rawRecordCount = 0;
        var groupingLinkCount = 0;
        for (final fixture in fixtures) {
          final raw = backend.analyzeRaw(fixture.normalizedText);
          final grouped = backend.analyze(fixture.normalizedText);
          expect(raw, hasLength(fixture.words.length), reason: fixture.caseId);
          expect(
            grouped,
            hasLength(fixture.words.length),
            reason: fixture.caseId,
          );
          rawRecordCount += raw.length;
          for (var index = 0; index < fixture.words.length; index++) {
            final expected = fixture.words[index];
            final actualRaw = raw[index];
            final actualGrouped = grouped[index];
            final reason = '${fixture.caseId} word $index';
            expect(actualRaw.surface, expected.surface, reason: reason);
            expect(
              actualRaw.pronunciation,
              expected.pronunciation,
              reason: '$reason pronunciation',
            );
            expect(actualRaw.kana, expected.kana, reason: '$reason kana');
            expect(
              actualRaw.charType,
              expected.charType,
              reason: '$reason charType',
            );
            expect(
              actualRaw.isUnknown,
              expected.isUnknown,
              reason: '$reason isUnknown',
            );
            expect(actualGrouped.surface, expected.surface, reason: reason);
            expect(
              actualGrouped.hiragana,
              expected.hiragana,
              reason: '$reason hiragana',
            );
            expect(
              actualGrouped.charType,
              expected.charType,
              reason: '$reason grouped charType',
            );
            expect(
              actualGrouped.isUnknown,
              expected.isUnknown,
              reason: '$reason grouped isUnknown',
            );
            expect(
              actualGrouped.joinWithNext,
              expected.joinWithNext,
              reason: '$reason joinWithNext',
            );
            if (actualGrouped.joinWithNext) groupingLinkCount++;
          }
        }
        expect(rawRecordCount, 126);
        expect(groupingLinkCount, 12);

        final engine = JapaneseCutletEngine(backend: backend);
        var successfulOutputs = 0;
        var pinnedFailures = 0;
        for (final fixture in fixtures) {
          if (fixture.errorCategory != null) {
            pinnedFailures++;
            expect(fixture.caseId, 'long-number-diagnostic');
            expect(fixture.errorCategory, 'upstreamFailure');
            expect(fixture.phonemes, isNull);
            expect(
              () => engine.convert(fixture.input),
              throwsA(
                isA<BackendFailureException>().having(
                  (error) => error.message,
                  'message',
                  'Japanese Cutlet morphology mecab-unidic-cutlet '
                      '0.996/unidic-3.1.0 returned invalid word 8: '
                      'surface `10` remained numeric after normalization.',
                ),
              ),
              reason: fixture.caseId,
            );
            continue;
          }
          successfulOutputs++;
          final result = engine.convert(fixture.input);
          expect(result.phonemes, fixture.phonemes, reason: fixture.caseId);
          expect(result.tokens, isNull, reason: fixture.caseId);
        }
        expect(successfulOutputs, 26);
        expect(pinnedFailures, 1);
      } finally {
        backend?.close();
        final bytes = wordListBytes;
        if (bytes != null) bytes.fillRange(0, bytes.length, 0);
        try {
          await resources?.delete();
        } finally {
          provisioner.close();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}

final class _LoopbackProvisioner {
  _LoopbackProvisioner._(this._baseUri, this._token)
    : _client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30)
        ..idleTimeout = const Duration(seconds: 30);

  factory _LoopbackProvisioner.fromEnvironment() {
    if (_resourceBaseUrl.isEmpty || _resourceToken.isEmpty) {
      throw StateError(
        'This provisioned test requires MISAKID_TEST_RESOURCE_BASE_URL and '
        'MISAKID_TEST_RESOURCE_TOKEN dart-defines.',
      );
    }
    final baseUri = Uri.tryParse(_resourceBaseUrl);
    if (baseUri == null ||
        baseUri.scheme != 'http' ||
        !_allowedLoopbackHosts.contains(baseUri.host) ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.query.isNotEmpty ||
        baseUri.fragment.isNotEmpty ||
        (baseUri.path.isNotEmpty && baseUri.path != '/')) {
      throw StateError(
        'The test resource URL must use an approved HTTP loopback host.',
      );
    }
    if (_resourceToken.runes.any(
      (scalar) => scalar <= 0x20 || scalar == 0x7f,
    )) {
      throw StateError('The test resource token contains whitespace.');
    }
    return _LoopbackProvisioner._(baseUri, _resourceToken);
  }

  static const _allowedLoopbackHosts = <String>{
    '10.0.2.2',
    '127.0.0.1',
    'localhost',
  };

  final Uri _baseUri;
  final String _token;
  final HttpClient _client;

  Future<_ProvisionedResources> provision() async {
    final root = await Directory.systemTemp.createTemp(
      'misakid-mobile-cutlet-',
    );
    try {
      final manifest = _ProvisioningManifest.parse(
        await _getJson(_baseUri.resolve('/v1/manifest.json')),
        _baseUri,
      );
      final dictionary = Directory('${root.path}/unidic-cwj');
      await dictionary.create();
      for (final file in manifest.dictionaryFiles) {
        await _download(file, File('${dictionary.path}/${file.path}'));
      }
      final wordList = File('${root.path}/ja_words.txt');
      final fixture = File('${root.path}/ja_cutlet.jsonl');
      await _download(manifest.wordList, wordList);
      await _download(manifest.fixture, fixture);
      return _ProvisionedResources(
        root: root,
        dictionary: dictionary,
        wordList: wordList,
        fixture: fixture,
      );
    } on Object {
      await root.delete(recursive: true);
      rethrow;
    }
  }

  Future<Object?> _getJson(Uri uri) async {
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        'Resource manifest returned HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response) {
      length += chunk.length;
      if (length > 1024 * 1024) {
        throw const FormatException('Resource manifest is too large.');
      }
      bytes.add(chunk);
    }
    return jsonDecode(utf8.decode(bytes.takeBytes(), allowMalformed: false));
  }

  Future<void> _download(_RemoteFile source, File destination) async {
    if (await destination.exists()) {
      throw StateError('Refusing to replace ${destination.path}.');
    }
    await destination.parent.create(recursive: true);
    final partial = File('${destination.path}.part');
    if (await partial.exists()) {
      throw StateError('Refusing to replace ${partial.path}.');
    }

    final request = await _client.getUrl(source.url);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        'Resource returned HTTP ${response.statusCode}.',
        uri: source.url,
      );
    }
    if (response.contentLength != source.bytes) {
      await response.drain<void>();
      throw StateError(
        '${source.url} declared ${response.contentLength} bytes; '
        'expected ${source.bytes}.',
      );
    }

    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    final output = partial.openWrite(mode: FileMode.writeOnly);
    var received = 0;
    try {
      try {
        await for (final chunk in response) {
          received += chunk.length;
          if (received > source.bytes) {
            throw StateError('${source.url} exceeded its expected size.');
          }
          hasher.add(chunk);
          output.add(chunk);
        }
      } finally {
        hasher.close();
        await output.close();
      }
      if (received != source.bytes || digestSink.value != source.sha256) {
        throw StateError(
          '${source.url} failed its streamed size or SHA-256 check.',
        );
      }
      await partial.rename(destination.path);
    } on Object {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  void close() => _client.close(force: true);
}

final class _ProvisionedResources {
  const _ProvisionedResources({
    required this.root,
    required this.dictionary,
    required this.wordList,
    required this.fixture,
  });

  final Directory root;
  final Directory dictionary;
  final File wordList;
  final File fixture;

  Future<void> delete() => root.delete(recursive: true);
}

final class _ProvisioningManifest {
  const _ProvisioningManifest({
    required this.dictionaryFiles,
    required this.wordList,
    required this.fixture,
  });

  factory _ProvisioningManifest.parse(Object? value, Uri baseUri) {
    final root = _map(value, 'manifest');
    _expectKeys(root, const <String>{
      'schemaVersion',
      'dictionary',
      'wordList',
      'fixture',
    }, 'manifest');
    _expectValue(root, 'schemaVersion', 1, 'manifest');

    final dictionary = _map(root['dictionary'], 'manifest.dictionary');
    _expectKeys(dictionary, const <String>{
      'name',
      'version',
      'treeSha256',
      'bytes',
      'files',
    }, 'manifest.dictionary');
    _expectValue(dictionary, 'name', 'unidic-cwj', 'manifest.dictionary');
    _expectValue(
      dictionary,
      'version',
      '3.1.0+2021-08-31',
      'manifest.dictionary',
    );
    _expectValue(
      dictionary,
      'treeSha256',
      _dictionaryTreeSha256,
      'manifest.dictionary',
    );
    _expectValue(dictionary, 'bytes', 811662881, 'manifest.dictionary');
    final dictionaryFiles = <_RemoteFile>[];
    final paths = <String>{};
    var dictionaryBytes = 0;
    final rawFiles = _list(dictionary['files'], 'manifest.dictionary.files');
    for (var index = 0; index < rawFiles.length; index++) {
      final file = _RemoteFile.parse(
        rawFiles[index],
        baseUri,
        'manifest.dictionary.files[$index]',
        requiresPath: true,
      );
      if (!paths.add(file.path)) {
        throw FormatException('Duplicate dictionary path ${file.path}.');
      }
      dictionaryBytes += file.bytes;
      dictionaryFiles.add(file);
    }
    if (paths.length != 20 ||
        !_dictionaryPaths.containsAll(paths) ||
        !paths.containsAll(_dictionaryPaths) ||
        dictionaryBytes != 811662881) {
      throw const FormatException('Dictionary manifest identity differs.');
    }

    final wordListMap = _map(root['wordList'], 'manifest.wordList');
    _expectKeys(wordListMap, const <String>{
      'url',
      'bytes',
      'sha256',
      'records',
    }, 'manifest.wordList');
    _expectValue(wordListMap, 'records', 147571, 'manifest.wordList');
    final wordList = _RemoteFile.parse(
      wordListMap,
      baseUri,
      'manifest.wordList',
      requiresPath: false,
    );
    if (wordList.bytes != 1921140 || wordList.sha256 != _wordListSha256) {
      throw const FormatException('Word-list manifest identity differs.');
    }

    final fixtureMap = _map(root['fixture'], 'manifest.fixture');
    _expectKeys(fixtureMap, const <String>{
      'url',
      'bytes',
      'sha256',
      'cases',
      'records',
    }, 'manifest.fixture');
    _expectValue(fixtureMap, 'cases', 27, 'manifest.fixture');
    _expectValue(fixtureMap, 'records', 126, 'manifest.fixture');
    final fixture = _RemoteFile.parse(
      fixtureMap,
      baseUri,
      'manifest.fixture',
      requiresPath: false,
    );
    if (fixture.bytes != 47945 || fixture.sha256 != _fixtureSha256) {
      throw const FormatException('Fixture manifest identity differs.');
    }
    return _ProvisioningManifest(
      dictionaryFiles: List<_RemoteFile>.unmodifiable(dictionaryFiles),
      wordList: wordList,
      fixture: fixture,
    );
  }

  final List<_RemoteFile> dictionaryFiles;
  final _RemoteFile wordList;
  final _RemoteFile fixture;
}

final class _RemoteFile {
  const _RemoteFile({
    required this.path,
    required this.url,
    required this.bytes,
    required this.sha256,
  });

  factory _RemoteFile.parse(
    Object? value,
    Uri baseUri,
    String location, {
    required bool requiresPath,
  }) {
    final root = _map(value, location);
    _expectKeys(
      root,
      requiresPath
          ? const <String>{'path', 'url', 'bytes', 'sha256'}
          : root.keys.toSet(),
      location,
    );
    final path = requiresPath ? _string(root, 'path', location) : '';
    if (requiresPath && !_validRelativePath(path)) {
      throw FormatException('$location.path is not a safe relative path.');
    }
    final rawUrl = _string(root, 'url', location);
    final url = baseUri.resolve(rawUrl);
    if (url.scheme != baseUri.scheme ||
        url.host != baseUri.host ||
        url.port != baseUri.port ||
        url.userInfo.isNotEmpty ||
        url.query.isNotEmpty ||
        url.fragment.isNotEmpty ||
        !url.path.startsWith('/v1/')) {
      throw FormatException('$location.url escapes the loopback origin.');
    }
    final bytes = _integer(root, 'bytes', location);
    final sha256 = _string(root, 'sha256', location);
    if (bytes <= 0 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw FormatException('$location has an invalid resource identity.');
    }
    return _RemoteFile(path: path, url: url, bytes: bytes, sha256: sha256);
  }

  final String path;
  final Uri url;
  final int bytes;
  final String sha256;
}

final class _DigestSink implements Sink<Digest> {
  String? value;

  @override
  void add(Digest data) {
    if (value != null) throw StateError('SHA-256 emitted more than once.');
    value = data.toString();
  }

  @override
  void close() {}
}

final class _CutletFixture {
  const _CutletFixture({
    required this.caseId,
    required this.input,
    required this.phonemes,
    required this.errorCategory,
    required this.normalizedText,
    required this.words,
  });

  factory _CutletFixture.parse(Object? value, int line) {
    final location = 'fixture line $line';
    final root = _map(value, location);
    final hasError = root.containsKey('error');
    _expectKeys(root, <String>{
      'backendInput',
      'backendVersions',
      'caseId',
      'input',
      'language',
      'mode',
      'options',
      'phonemes',
      'schemaVersion',
      'tokens',
      'upstreamCommit',
      'upstreamRepository',
      'upstreamVersion',
      if (hasError) 'error',
    }, location);
    _expectValue(root, 'schemaVersion', 1, location);
    _expectValue(root, 'upstreamRepository', 'hexgrad/misaki', location);
    _expectValue(root, 'upstreamCommit', _upstreamCommit, location);
    _expectValue(root, 'upstreamVersion', '0.9.4', location);
    _expectValue(root, 'language', 'ja', location);
    _expectValue(root, 'mode', 'cutlet', location);
    if (_map(root['options'], '$location.options').isNotEmpty) {
      throw FormatException('$location.options must be empty.');
    }
    if (root['tokens'] != null) {
      throw FormatException('$location.tokens must be null.');
    }

    final backendVersions = _stringMap(
      root['backendVersions'],
      '$location.backendVersions',
    );
    _expectMapValue(backendVersions, 'fugashi', '1.4.0', location);
    _expectMapValue(backendVersions, 'jaconv', '0.4.0', location);
    _expectMapValue(backendVersions, 'unicode-data', '15.0.0', location);
    _expectMapValue(
      backendVersions,
      'misaki-ja-words',
      'sha256:$_wordListSha256+bytes:1921140+records:147571',
      location,
    );
    _expectMapValue(
      backendVersions,
      'unidic-dictionary-tree',
      'sha256:$_dictionaryTreeSha256+files:20+bytes:811662881',
      location,
    );
    _expectMapValue(
      backendVersions,
      'fugashi-system-dictionary',
      'charset:utf8+entries:878989+binary-version:102',
      location,
    );

    final backendInput = _map(root['backendInput'], '$location.backendInput');
    _expectKeys(backendInput, const <String>{
      'kind',
      'normalizedText',
      'schemaVersion',
      'words',
    }, '$location.backendInput');
    _expectValue(
      backendInput,
      'kind',
      'misaki.cutlet.normalized-morphology',
      '$location.backendInput',
    );
    _expectValue(backendInput, 'schemaVersion', 1, '$location.backendInput');
    final rawWords = _list(
      backendInput['words'],
      '$location.backendInput.words',
    );
    final words = <_CutletWord>[];
    for (var index = 0; index < rawWords.length; index++) {
      words.add(
        _CutletWord.parse(
          rawWords[index],
          '$location.backendInput.words[$index]',
          isLast: index + 1 == rawWords.length,
        ),
      );
    }

    String? errorCategory;
    if (hasError) {
      final error = _map(root['error'], '$location.error');
      _expectKeys(error, const <String>{'category'}, '$location.error');
      errorCategory = _string(error, 'category', '$location.error');
      if (root['phonemes'] != null) {
        throw FormatException('$location.phonemes must be null on failure.');
      }
    } else if (root['phonemes'] is! String) {
      throw FormatException('$location.phonemes must be a string.');
    }
    return _CutletFixture(
      caseId: _string(root, 'caseId', location),
      input: _string(root, 'input', location),
      phonemes: root['phonemes'] as String?,
      errorCategory: errorCategory,
      normalizedText: _string(
        backendInput,
        'normalizedText',
        '$location.backendInput',
      ),
      words: List<_CutletWord>.unmodifiable(words),
    );
  }

  final String caseId;
  final String input;
  final String? phonemes;
  final String? errorCategory;
  final String normalizedText;
  final List<_CutletWord> words;
}

final class _CutletWord {
  const _CutletWord({
    required this.surface,
    required this.pronunciation,
    required this.kana,
    required this.hiragana,
    required this.charType,
    required this.isUnknown,
    required this.joinWithNext,
  });

  factory _CutletWord.parse(
    Object? value,
    String location, {
    required bool isLast,
  }) {
    final root = _map(value, location);
    _expectKeys(root, const <String>{
      'surface',
      'pronunciation',
      'kana',
      'hiragana',
      'charType',
      'isUnknown',
      'joinWithNext',
    }, location);
    final surface = _string(root, 'surface', location);
    final hiragana = _string(root, 'hiragana', location);
    final charType = _integer(root, 'charType', location);
    final isUnknown = _boolean(root, 'isUnknown', location);
    final joinWithNext = _boolean(root, 'joinWithNext', location);
    if (surface.isEmpty || hiragana.isEmpty || charType < 0) {
      throw FormatException('$location has an invalid required field.');
    }
    if (joinWithNext && isLast) {
      throw FormatException('$location joins past the final record.');
    }
    return _CutletWord(
      surface: surface,
      pronunciation: _nullableString(root, 'pronunciation', location),
      kana: _nullableString(root, 'kana', location),
      hiragana: hiragana,
      charType: charType,
      isUnknown: isUnknown,
      joinWithNext: joinWithNext,
    );
  }

  final String surface;
  final String? pronunciation;
  final String? kana;
  final String hiragana;
  final int charType;
  final bool isUnknown;
  final bool joinWithNext;
}

Future<List<_CutletFixture>> _readFixtures(File file) async {
  final fixtures = <_CutletFixture>[];
  var lineNumber = 0;
  await for (final line
      in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    lineNumber++;
    fixtures.add(_CutletFixture.parse(jsonDecode(line), lineNumber));
  }
  return List<_CutletFixture>.unmodifiable(fixtures);
}

void _expectFixtureContract(List<_CutletFixture> fixtures) {
  expect(fixtures, hasLength(27));
  expect(fixtures.map((fixture) => fixture.caseId).toSet(), hasLength(27));
  expect(
    fixtures.where((fixture) => fixture.errorCategory == null),
    hasLength(26),
  );
  expect(
    fixtures.where((fixture) => fixture.errorCategory != null),
    hasLength(1),
  );
  final words = fixtures.expand((fixture) => fixture.words).toList();
  expect(words, hasLength(126));
  expect(words.where((word) => word.joinWithNext), hasLength(12));
  expect(words.where((word) => word.isUnknown), hasLength(26));
  expect(words.where((word) => word.pronunciation == null), hasLength(26));
  expect(words.where((word) => word.pronunciation != null), hasLength(100));
  expect(words.where((word) => word.kana == null), hasLength(26));
  expect(words.where((word) => word.kana != null), hasLength(100));
  final failure = fixtures.singleWhere(
    (fixture) => fixture.caseId == 'long-number-diagnostic',
  );
  expect(failure.input, '1234567890');
  expect(failure.errorCategory, 'upstreamFailure');
  expect(failure.phonemes, isNull);
  expect(failure.words, hasLength(10));
}

Map<String, Object?> _map(Object? value, String location) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('$location must be an object.');
}

Map<String, String> _stringMap(Object? value, String location) {
  final source = _map(value, location);
  final result = <String, String>{};
  for (final entry in source.entries) {
    final item = entry.value;
    if (item is! String) {
      throw FormatException('$location.${entry.key} must be a string.');
    }
    result[entry.key] = item;
  }
  return result;
}

List<Object?> _list(Object? value, String location) {
  if (value is List<Object?>) return value;
  throw FormatException('$location must be an array.');
}

String _string(Map<String, Object?> value, String key, String location) {
  final result = value[key];
  if (result is String) return result;
  throw FormatException('$location.$key must be a string.');
}

String? _nullableString(
  Map<String, Object?> value,
  String key,
  String location,
) {
  if (!value.containsKey(key)) {
    throw FormatException('$location.$key is missing.');
  }
  final result = value[key];
  if (result == null || result is String) return result as String?;
  throw FormatException('$location.$key must be null or a string.');
}

int _integer(Map<String, Object?> value, String key, String location) {
  final result = value[key];
  if (result is int) return result;
  throw FormatException('$location.$key must be an integer.');
}

bool _boolean(Map<String, Object?> value, String key, String location) {
  final result = value[key];
  if (result is bool) return result;
  throw FormatException('$location.$key must be a boolean.');
}

void _expectKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String location,
) {
  if (value.length != expected.length || !expected.every(value.containsKey)) {
    throw FormatException(
      '$location keys ${value.keys.toList()..sort()} differ from '
      '${expected.toList()..sort()}.',
    );
  }
}

void _expectValue(
  Map<String, Object?> value,
  String key,
  Object expected,
  String location,
) {
  if (value[key] != expected) {
    throw FormatException('$location.$key differs from $expected.');
  }
}

void _expectMapValue(
  Map<String, String> value,
  String key,
  String expected,
  String location,
) {
  if (value[key] != expected) {
    throw FormatException('$location.backendVersions.$key differs.');
  }
}

bool _validRelativePath(String value) {
  final parts = value.split('/');
  return value.isNotEmpty &&
      !value.startsWith('/') &&
      parts.every(
        (part) =>
            part.isNotEmpty &&
            part != '.' &&
            part != '..' &&
            !part.contains('\\'),
      );
}
