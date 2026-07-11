import 'package:misakid/misaki_vi.dart';
import 'package:test/test.dart';

import 'upstream_fixture.dart';

/// Strict one-call replay of a captured underthesea tokenizer boundary.
final class VietnameseFixtureTokenizerReplay
    implements VietnameseTokenizerBackend {
  VietnameseFixtureTokenizerReplay(this.fixture);

  final VietnameseFixtureBackendInput fixture;
  final List<String> inputs = <String>[];

  @override
  final BackendInfo info = BackendInfo(
    name: 'committed-underthesea-token-replay',
    version: '6.8.4',
  );

  @override
  List<String> tokenize(String text) {
    inputs.add(text);
    if (inputs.length != 1) {
      throw StateError(
        'Vietnamese fixture tokenizer was called more than once.',
      );
    }
    if (text != fixture.input) {
      throw StateError('Expected `${fixture.input}`, got `$text`.');
    }
    return List<String>.of(fixture.tokens);
  }

  void expectComplete(String reason) {
    expect(inputs, <String>[fixture.input], reason: reason);
  }
}

/// Compares every pinned Vietnamese MToken field and typed metadata value.
void expectVietnameseFixtureTokens(
  List<MisakiToken>? actual,
  List<Object?>? expected,
  String reason,
) {
  expect(actual, isNotNull, reason: reason);
  expect(expected, isNotNull, reason: reason);
  final actualTokens = actual!;
  final expectedTokens = expected!;
  expect(actualTokens, hasLength(expectedTokens.length), reason: reason);
  for (var index = 0; index < expectedTokens.length; index++) {
    final raw = expectedTokens[index];
    final tokenReason = '$reason token $index';
    expect(raw, isA<Map<String, Object?>>(), reason: tokenReason);
    final expectedToken = raw! as Map<String, Object?>;
    expect(expectedToken.keys.toSet(), const <String>{
      '_',
      'end_ts',
      'phonemes',
      'start_ts',
      'tag',
      'text',
      'whitespace',
    }, reason: tokenReason);
    final actualToken = actualTokens[index];
    expect(actualToken.text, expectedToken['text'], reason: tokenReason);
    expect(actualToken.tag, expectedToken['tag'], reason: tokenReason);
    expect(
      actualToken.whitespace,
      expectedToken['whitespace'],
      reason: tokenReason,
    );
    expect(
      actualToken.phonemes,
      expectedToken['phonemes'],
      reason: tokenReason,
    );
    expect(
      actualToken.startTimeSeconds,
      expectedToken['start_ts'],
      reason: tokenReason,
    );
    expect(
      actualToken.endTimeSeconds,
      expectedToken['end_ts'],
      reason: tokenReason,
    );

    final expectedMetadata = expectedToken['_'];
    if (expectedMetadata == null) {
      expect(actualToken.metadata, isNull, reason: tokenReason);
      continue;
    }
    expect(expectedMetadata, isA<Map<String, Object?>>(), reason: tokenReason);
    final metadata = expectedMetadata as Map<String, Object?>;
    expect(metadata.keys.toSet(), const <String>{
      'codas',
      'nuclei',
      'onsets',
      'parent',
      'tone',
    }, reason: tokenReason);
    expect(
      actualToken.metadata,
      isA<VietnameseTokenMetadata>(),
      reason: tokenReason,
    );
    final actualMetadata = actualToken.metadata! as VietnameseTokenMetadata;
    expect(actualMetadata.parent, metadata['parent'], reason: tokenReason);
    expect(actualMetadata.onset, metadata['onsets'], reason: tokenReason);
    expect(actualMetadata.nucleus, metadata['nuclei'], reason: tokenReason);
    expect(actualMetadata.coda, metadata['codas'], reason: tokenReason);
    expect(actualMetadata.tone, metadata['tone'], reason: tokenReason);
  }
}
