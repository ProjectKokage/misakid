import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:misakid/misaki_ja.dart';
import 'package:misakid_openjtalk/misakid_openjtalk.dart';
import 'package:misakid_openjtalk/src/native_bindings.dart';

const _resourceBaseUrl = String.fromEnvironment(
  'MISAKID_OPENJTALK_TEST_RESOURCE_BASE_URL',
);
const _resourceToken = String.fromEnvironment(
  'MISAKID_OPENJTALK_TEST_RESOURCE_TOKEN',
);
const _fixtureSha256 =
    'fb9832f6f4a62187d119f7acceca8e432004d1c069326fb239899a752b5e2b7e';
const _fixtureBytes = 77134;
const _dictionaryTreeSha256 =
    '8b26c37228c9e9b92333e612e1144c958f2788d219e46c8652f698a089be1ccc';
const _dictionaryBytes = 107304813;
const _upstreamCommit = 'fba1236595f2d2bf21d414ba6e57d25256afada3';

const _dictionaryFiles = <String, ({int bytes, String sha256})>{
  'COPYING': (
    bytes: 5865,
    sha256: 'f4eca42ebd930e2c6e57fca58319d989bebcd1510cb7714b149c50f5425135ea',
  ),
  'char.bin': (
    bytes: 262496,
    sha256: '888ee94c5a8a7a26d24ab3f1b7155441351954fd51ea06b4a2f78bd742492b2f',
  ),
  'left-id.def': (
    bytes: 77672,
    sha256: 'db1adac8a7f9e5854cd82ea044c85115249206c8181b9d88cf92ae2ee5e87b84',
  ),
  'matrix.bin': (
    bytes: 3792262,
    sha256: '62fd16b4f64c851d5dc352ef0d5740c5fc83ddc7c203b2b0b1fc5271969a14ce',
  ),
  'pos-id.def': (
    bytes: 1923,
    sha256: '3460aa742053085af47cdfc889a1e0e6f557e89b406e501ba81c9ccc286de0c7',
  ),
  'rewrite.def': (
    bytes: 7457,
    sha256: '7f7c8dfbfe24092e8a149a9b6e0a3a7f1c2cf37d6c3dc29d1cccc6c004da9c1c',
  ),
  'right-id.def': (
    bytes: 77672,
    sha256: 'db1adac8a7f9e5854cd82ea044c85115249206c8181b9d88cf92ae2ee5e87b84',
  ),
  'sys.dic': (
    bytes: 103073776,
    sha256: 'ca57d9029691a70a5dfb99afc2844180256161d7130da65b1a867510e129b9a6',
  ),
  'unk.dic': (
    bytes: 5690,
    sha256: 'ce97851ecda075914fa3ffe7294a1ab34ee4f6d56ba6bf9197d74143b5dffbfe',
  ),
};

const _stringFields = <String>[
  'string',
  'pos',
  'pos_group1',
  'pos_group2',
  'pos_group3',
  'ctype',
  'cform',
  'orig',
  'read',
  'pron',
  'chain_rule',
];
const _integerFields = <String>['acc', 'mora_size', 'chain_flag'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'bundled Open JTalk matches every pinned Japanese frontend fixture',
    (_) async {
      final provisioner = _LoopbackProvisioner.fromEnvironment();
      _ProvisionedResources? resources;
      OpenJtalkNativeFrontend? rawFrontend;
      OpenJtalkFrontendBackend? backend;
      try {
        final provisioned = await provisioner.provision();
        resources = provisioned;
        final fixtures = await _readFixtures(provisioned.fixture);
        _expectFixtureContract(fixtures);

        backend = await OpenJtalkFrontendBackend.openBundled(
          dictionaryPath: provisioned.dictionary.path,
        );
        final nativeLibrary = OpenJtalkNativeLibrary.loadBundled();
        rawFrontend = OpenJtalkNativeFrontend.create(
          library: nativeLibrary,
          dictionaryPath: provisioned.dictionary.path,
          maxInputBytes: defaultOpenJtalkMaxInputBytes,
        );

        expect(nativeLibrary.identities, expectedOpenJtalkNativeIdentities);
        expect(backend.info.name, 'pyopenjtalk');
        expect(backend.info.version, '0.4.1');
        expect(
          backend.info.details['platform'],
          'native-assets-${Abi.current()}',
        );
        expect(backend.info.details['openJtalkVersion'], '1.11');
        expect(
          backend.info.details['nativePatchSet'],
          'misakid-openjtalk-safety-v1',
        );
        expect(backend.info.details['dictionary'], 'open_jtalk_dic_utf_8-1.11');
        expect(
          backend.info.details['dictionaryTreeSha256'],
          _dictionaryTreeSha256,
        );

        var rawRecordCount = 0;
        for (final fixture in fixtures) {
          final actual = rawFrontend.analyzeRaw(fixture.input);
          expect(
            actual,
            hasLength(fixture.words.length),
            reason: fixture.caseId,
          );
          rawRecordCount += actual.length;
          for (var wordIndex = 0; wordIndex < actual.length; wordIndex++) {
            final expected = fixture.words[wordIndex];
            final word = actual[wordIndex];
            for (var field = 0; field < _stringFields.length; field++) {
              expect(
                word.stringFields[field],
                expected.stringFields[field],
                reason:
                    '${fixture.caseId} word $wordIndex ${_stringFields[field]}',
              );
            }
            for (var field = 0; field < _integerFields.length; field++) {
              expect(
                word.integerFields[field],
                expected.integerFields[field],
                reason:
                    '${fixture.caseId} word $wordIndex ${_integerFields[field]}',
              );
            }
          }
        }
        expect(rawRecordCount, 155);

        final engine = JapanesePyopenjtalkEngine(backend: backend);
        var successfulOutputs = 0;
        var pinnedFailures = 0;
        for (final fixture in fixtures) {
          if (fixture.errorCategory != null) {
            pinnedFailures++;
            expect(fixture.caseId, 'whitespace-only');
            expect(fixture.errorCategory, 'upstreamFailure');
            expect(fixture.phonemes, isNull);
            expect(fixture.tokens, isNull);
            expect(
              () => engine.convert(fixture.input),
              throwsA(
                isA<BackendFailureException>().having(
                  (error) => error.message,
                  'message',
                  'Japanese frontend pyopenjtalk 0.4.1 returned invalid word '
                      '0: leading whitespace cannot attach to a preceding '
                      'token.',
                ),
              ),
              reason: fixture.caseId,
            );
            continue;
          }
          successfulOutputs++;
          final result = engine.convert(fixture.input);
          expect(result.phonemes, fixture.phonemes, reason: fixture.caseId);
          _expectTokens(result.tokens, fixture.tokens, fixture.caseId);
        }
        expect(successfulOutputs, 23);
        expect(pinnedFailures, 1);
      } finally {
        rawFrontend?.close();
        backend?.close();
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
        'This provisioned test requires '
        'MISAKID_OPENJTALK_TEST_RESOURCE_BASE_URL and '
        'MISAKID_OPENJTALK_TEST_RESOURCE_TOKEN dart-defines.',
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
      'misakid-mobile-openjtalk-',
    );
    try {
      final manifest = _ProvisioningManifest.parse(
        await _getJson(_baseUri.resolve('/v1/manifest.json')),
        _baseUri,
      );
      final dictionary = Directory('${root.path}/open_jtalk_dic_utf_8-1.11');
      await dictionary.create();
      for (final file in manifest.dictionaryFiles) {
        await _download(file, File('${dictionary.path}/${file.path}'));
      }
      final fixture = File('${root.path}/ja_pyopenjtalk.jsonl');
      await _download(manifest.fixture, fixture);
      return _ProvisionedResources(
        root: root,
        dictionary: dictionary,
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
    required this.fixture,
  });

  final Directory root;
  final Directory dictionary;
  final File fixture;

  Future<void> delete() => root.delete(recursive: true);
}

final class _ProvisioningManifest {
  const _ProvisioningManifest({
    required this.dictionaryFiles,
    required this.fixture,
  });

  factory _ProvisioningManifest.parse(Object? value, Uri baseUri) {
    final root = _map(value, 'manifest');
    _expectKeys(root, const <String>{
      'schemaVersion',
      'dictionary',
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
    _expectValue(
      dictionary,
      'name',
      'open_jtalk_dic_utf_8-1.11',
      'manifest.dictionary',
    );
    _expectValue(dictionary, 'version', '1.11', 'manifest.dictionary');
    _expectValue(
      dictionary,
      'treeSha256',
      _dictionaryTreeSha256,
      'manifest.dictionary',
    );
    _expectValue(dictionary, 'bytes', _dictionaryBytes, 'manifest.dictionary');

    final rawFiles = _list(dictionary['files'], 'manifest.dictionary.files');
    final expectedNames = _dictionaryFiles.keys.toList(growable: false)..sort();
    if (rawFiles.length != expectedNames.length) {
      throw const FormatException('Dictionary manifest file count differs.');
    }
    final dictionaryFiles = <_RemoteFile>[];
    var dictionaryBytes = 0;
    for (var index = 0; index < rawFiles.length; index++) {
      final expectedName = expectedNames[index];
      final expected = _dictionaryFiles[expectedName]!;
      final file = _RemoteFile.parse(
        rawFiles[index],
        baseUri,
        'manifest.dictionary.files[$index]',
        requiresPath: true,
      );
      if (file.path != expectedName ||
          file.url.path != '/v1/dictionary/$expectedName' ||
          file.bytes != expected.bytes ||
          file.sha256 != expected.sha256) {
        throw FormatException(
          'Dictionary manifest identity differs for $expectedName.',
        );
      }
      dictionaryBytes += file.bytes;
      dictionaryFiles.add(file);
    }
    if (dictionaryBytes != _dictionaryBytes) {
      throw const FormatException('Dictionary manifest byte total differs.');
    }

    final fixtureMap = _map(root['fixture'], 'manifest.fixture');
    _expectKeys(fixtureMap, const <String>{
      'url',
      'bytes',
      'sha256',
      'cases',
      'records',
      'successes',
      'failures',
    }, 'manifest.fixture');
    _expectValue(fixtureMap, 'cases', 24, 'manifest.fixture');
    _expectValue(fixtureMap, 'records', 155, 'manifest.fixture');
    _expectValue(fixtureMap, 'successes', 23, 'manifest.fixture');
    _expectValue(fixtureMap, 'failures', 1, 'manifest.fixture');
    final fixture = _RemoteFile.parse(
      fixtureMap,
      baseUri,
      'manifest.fixture',
      requiresPath: false,
    );
    if (fixture.url.path != '/v1/fixture' ||
        fixture.bytes != _fixtureBytes ||
        fixture.sha256 != _fixtureSha256) {
      throw const FormatException('Fixture manifest identity differs.');
    }
    return _ProvisioningManifest(
      dictionaryFiles: List<_RemoteFile>.unmodifiable(dictionaryFiles),
      fixture: fixture,
    );
  }

  final List<_RemoteFile> dictionaryFiles;
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
          : const <String>{
              'url',
              'bytes',
              'sha256',
              'cases',
              'records',
              'successes',
              'failures',
            },
      location,
    );
    final path = requiresPath ? _string(root, 'path', location) : '';
    if (requiresPath && !_dictionaryFiles.containsKey(path)) {
      throw FormatException('$location.path is not a pinned dictionary file.');
    }
    final rawUrl = _string(root, 'url', location);
    if (!rawUrl.startsWith('/v1/')) {
      throw FormatException('$location.url is not a fixed resource route.');
    }
    final url = baseUri.resolve(rawUrl);
    if (url.scheme != baseUri.scheme ||
        url.host != baseUri.host ||
        url.port != baseUri.port ||
        url.userInfo.isNotEmpty ||
        url.query.isNotEmpty ||
        url.fragment.isNotEmpty) {
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

final class _OpenJtalkFixture {
  const _OpenJtalkFixture({
    required this.caseId,
    required this.input,
    required this.phonemes,
    required this.errorCategory,
    required this.words,
    required this.tokens,
  });

  factory _OpenJtalkFixture.parse(Object? value, int line) {
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
    _expectValue(root, 'mode', 'pyopenjtalk', location);
    if (_map(root['options'], '$location.options').isNotEmpty) {
      throw FormatException('$location.options must be empty.');
    }

    final backendVersions = _map(
      root['backendVersions'],
      '$location.backendVersions',
    );
    _expectKeys(backendVersions, const <String>{
      'pyopenjtalk',
    }, '$location.backendVersions');
    _expectValue(
      backendVersions,
      'pyopenjtalk',
      '0.4.1',
      '$location.backendVersions',
    );

    final backendInput = _map(root['backendInput'], '$location.backendInput');
    _expectKeys(backendInput, const <String>{
      'kind',
      'schemaVersion',
      'words',
    }, '$location.backendInput');
    _expectValue(
      backendInput,
      'kind',
      'pyopenjtalk.run_frontend.words',
      '$location.backendInput',
    );
    _expectValue(backendInput, 'schemaVersion', 1, '$location.backendInput');
    final rawWords = _list(
      backendInput['words'],
      '$location.backendInput.words',
    );
    final words = <_ExpectedRawWord>[];
    for (var index = 0; index < rawWords.length; index++) {
      words.add(
        _ExpectedRawWord.parse(
          rawWords[index],
          '$location.backendInput.words[$index]',
        ),
      );
    }

    String? phonemes;
    String? errorCategory;
    List<_ExpectedToken>? tokens;
    if (hasError) {
      final error = _map(root['error'], '$location.error');
      _expectKeys(error, const <String>{'category'}, '$location.error');
      errorCategory = _string(error, 'category', '$location.error');
      if (root['phonemes'] != null || root['tokens'] != null) {
        throw FormatException(
          '$location failure must have null phonemes and tokens.',
        );
      }
    } else {
      phonemes = _string(root, 'phonemes', location);
      final rawTokens = _list(root['tokens'], '$location.tokens');
      tokens = <_ExpectedToken>[
        for (var index = 0; index < rawTokens.length; index++)
          _ExpectedToken.parse(rawTokens[index], '$location.tokens[$index]'),
      ];
    }

    return _OpenJtalkFixture(
      caseId: _string(root, 'caseId', location),
      input: _string(root, 'input', location),
      phonemes: phonemes,
      errorCategory: errorCategory,
      words: List<_ExpectedRawWord>.unmodifiable(words),
      tokens: tokens == null ? null : List<_ExpectedToken>.unmodifiable(tokens),
    );
  }

  final String caseId;
  final String input;
  final String? phonemes;
  final String? errorCategory;
  final List<_ExpectedRawWord> words;
  final List<_ExpectedToken>? tokens;
}

final class _ExpectedRawWord {
  const _ExpectedRawWord({
    required this.stringFields,
    required this.integerFields,
  });

  factory _ExpectedRawWord.parse(Object? value, String location) {
    final root = _map(value, location);
    _expectKeys(root, <String>{..._stringFields, ..._integerFields}, location);
    return _ExpectedRawWord(
      stringFields: <String>[
        for (final field in _stringFields) _string(root, field, location),
      ],
      integerFields: <int>[
        for (final field in _integerFields) _integer(root, field, location),
      ],
    );
  }

  final List<String> stringFields;
  final List<int> integerFields;
}

final class _ExpectedToken {
  const _ExpectedToken({
    required this.text,
    required this.tag,
    required this.whitespace,
    required this.phonemes,
    required this.pronunciation,
    required this.accent,
    required this.moraSize,
    required this.chainFlag,
    required this.moras,
    required this.accents,
    required this.pitch,
  });

  factory _ExpectedToken.parse(Object? value, String location) {
    final root = _map(value, location);
    _expectKeys(root, const <String>{
      '_',
      'end_ts',
      'phonemes',
      'start_ts',
      'tag',
      'text',
      'whitespace',
    }, location);
    if (root['start_ts'] != null || root['end_ts'] != null) {
      throw FormatException('$location timestamps must be null.');
    }
    final metadata = _map(root['_'], '$location._');
    _expectKeys(metadata, const <String>{
      'acc',
      'accents',
      'chain_flag',
      'mora_size',
      'moras',
      'pitch',
      'pron',
    }, '$location._');
    return _ExpectedToken(
      text: _string(root, 'text', location),
      tag: _string(root, 'tag', location),
      whitespace: _string(root, 'whitespace', location),
      phonemes: _nullableString(root, 'phonemes', location),
      pronunciation: _string(metadata, 'pron', '$location._'),
      accent: _integer(metadata, 'acc', '$location._'),
      moraSize: _integer(metadata, 'mora_size', '$location._'),
      chainFlag: _fixtureBool(metadata['chain_flag'], '$location._.chain_flag'),
      moras: _stringList(metadata['moras'], '$location._.moras'),
      accents: _integerList(metadata['accents'], '$location._.accents'),
      pitch: _nullableString(metadata, 'pitch', '$location._'),
    );
  }

  final String text;
  final String tag;
  final String whitespace;
  final String? phonemes;
  final String pronunciation;
  final int accent;
  final int moraSize;
  final bool chainFlag;
  final List<String> moras;
  final List<int> accents;
  final String? pitch;
}

Future<List<_OpenJtalkFixture>> _readFixtures(File file) async {
  final fixtures = <_OpenJtalkFixture>[];
  var lineNumber = 0;
  await for (final line
      in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    lineNumber++;
    fixtures.add(_OpenJtalkFixture.parse(jsonDecode(line), lineNumber));
  }
  return List<_OpenJtalkFixture>.unmodifiable(fixtures);
}

void _expectFixtureContract(List<_OpenJtalkFixture> fixtures) {
  expect(fixtures, hasLength(24));
  expect(fixtures.map((fixture) => fixture.caseId).toSet(), hasLength(24));
  expect(
    fixtures.where((fixture) => fixture.errorCategory == null),
    hasLength(23),
  );
  expect(
    fixtures.where((fixture) => fixture.errorCategory != null),
    hasLength(1),
  );
  expect(fixtures.expand((fixture) => fixture.words), hasLength(155));
  expect(
    fixtures
        .where((fixture) => fixture.tokens != null)
        .expand((fixture) => fixture.tokens!),
    hasLength(147),
  );
  final failure = fixtures.singleWhere(
    (fixture) => fixture.caseId == 'whitespace-only',
  );
  expect(failure.input, ' \t\n　');
  expect(failure.errorCategory, 'upstreamFailure');
  expect(failure.words, hasLength(2));
  expect(failure.phonemes, isNull);
  expect(failure.tokens, isNull);
}

void _expectTokens(
  List<MisakiToken>? actual,
  List<_ExpectedToken>? expected,
  String caseId,
) {
  if (actual == null || expected == null) {
    fail('$caseId unexpectedly lacks a token list.');
  }
  expect(actual, hasLength(expected.length), reason: caseId);
  for (var index = 0; index < actual.length; index++) {
    final token = actual[index];
    final expectedToken = expected[index];
    final reason = '$caseId token $index';
    expect(token.text, expectedToken.text, reason: '$reason text');
    expect(token.tag, expectedToken.tag, reason: '$reason tag');
    expect(
      token.whitespace,
      expectedToken.whitespace,
      reason: '$reason whitespace',
    );
    expect(token.phonemes, expectedToken.phonemes, reason: '$reason phonemes');
    expect(token.startTimeSeconds, isNull, reason: '$reason start timestamp');
    expect(token.endTimeSeconds, isNull, reason: '$reason end timestamp');
    final metadata = token.metadata;
    if (metadata is! JapaneseTokenMetadata) {
      fail('$reason has no Japanese metadata.');
    }
    expect(
      metadata.pronunciation,
      expectedToken.pronunciation,
      reason: '$reason pronunciation',
    );
    expect(metadata.accent, expectedToken.accent, reason: '$reason accent');
    expect(
      metadata.moraSize,
      expectedToken.moraSize,
      reason: '$reason mora size',
    );
    expect(
      metadata.chainFlag,
      expectedToken.chainFlag,
      reason: '$reason chain flag',
    );
    expect(metadata.moras, expectedToken.moras, reason: '$reason moras');
    expect(metadata.accents, expectedToken.accents, reason: '$reason accents');
    expect(metadata.pitch, expectedToken.pitch, reason: '$reason pitch');
  }
}

Map<String, Object?> _map(Object? value, String location) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('$location must be an object.');
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

List<String> _stringList(Object? value, String location) {
  final source = _list(value, location);
  final result = <String>[];
  for (var index = 0; index < source.length; index++) {
    final item = source[index];
    if (item is! String) {
      throw FormatException('$location[$index] must be a string.');
    }
    result.add(item);
  }
  return List<String>.unmodifiable(result);
}

List<int> _integerList(Object? value, String location) {
  final source = _list(value, location);
  final result = <int>[];
  for (var index = 0; index < source.length; index++) {
    final item = source[index];
    if (item is! int) {
      throw FormatException('$location[$index] must be an integer.');
    }
    result.add(item);
  }
  return List<int>.unmodifiable(result);
}

bool _fixtureBool(Object? value, String location) {
  if (value is bool) return value;
  if (value is List<Object?> && value.isEmpty) return false;
  throw FormatException('$location must be a bool or the pinned empty list.');
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
