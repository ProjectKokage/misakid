import 'dart:convert';
import 'dart:io';

import 'package:misakid/misaki_en.dart';
import 'package:misakid/misaki_ja.dart';

const _corpusPath = 'benchmark/corpus/v1.json';

void main(List<String> arguments) {
  final iterations = _parseIterations(arguments);
  final corpus = _BenchmarkCorpus.load(File(_corpusPath));
  final rssAtStart = ProcessInfo.currentRss;

  final americanCold = _coldEnglishLookup(
    corpus.english.first,
    EnglishDialect.american,
  );
  final britishCold = _coldEnglishLookup(
    corpus.english.first,
    EnglishDialect.british,
  );

  var checksum = 0;
  final englishSamples = <int>[];
  for (var iteration = 0; iteration < iterations; iteration++) {
    final stopwatch = Stopwatch()..start();
    for (final dialect in EnglishDialect.values) {
      final lexicon = PinnedEnglishLexicon(dialect: dialect);
      for (final item in corpus.english) {
        final pronunciation = lexicon.lookup(
          item.token,
          const EnglishTokenContext(),
        );
        checksum = _mix(checksum, pronunciation?.phonemes ?? '');
      }
    }
    stopwatch.stop();
    englishSamples.add(stopwatch.elapsedMicroseconds);
  }

  const numbers = JapaneseNumberConverter();
  final japaneseSamples = <int>[];
  for (var iteration = 0; iteration < iterations; iteration++) {
    final stopwatch = Stopwatch()..start();
    for (final input in corpus.japaneseNumbers) {
      checksum = _mix(checksum, numbers.convert(input));
    }
    stopwatch.stop();
    japaneseSamples.add(stopwatch.elapsedMicroseconds);
  }

  final generatedBytes = Directory('lib/src/generated')
      .listSync()
      .whereType<File>()
      .fold<int>(0, (total, file) => total + file.lengthSync());

  final report = <String, Object?>{
    'schemaVersion': 1,
    'upstreamCommit': corpus.upstreamCommit,
    'dartVersion': Platform.version,
    'operatingSystem': Platform.operatingSystem,
    'iterations': iterations,
    'coldEnglish': <String, Object?>{
      'american': americanCold,
      'british': britishCold,
    },
    'warmEnglish': _summarize(
      englishSamples,
      operationsPerSample: corpus.english.length * EnglishDialect.values.length,
    ),
    'warmJapaneseNumbers': _summarize(
      japaneseSamples,
      operationsPerSample: corpus.japaneseNumbers.length,
    ),
    'memory': <String, int>{
      'rssAtStartBytes': rssAtStart,
      'rssAtEndBytes': ProcessInfo.currentRss,
      'generatedRuntimeSourceBytes': generatedBytes,
    },
    'checksum': checksum,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}

int _parseIterations(List<String> arguments) {
  const prefix = '--iterations=';
  final value = arguments
      .where((argument) => argument.startsWith(prefix))
      .map((argument) => argument.substring(prefix.length))
      .firstOrNull;
  final iterations = value == null ? 200 : int.tryParse(value);
  if (iterations == null || iterations < 1) {
    stderr.writeln(
      'Usage: dart run benchmark/misakid_benchmark.dart '
      '[--iterations=<positive integer>]',
    );
    exit(64);
  }
  return iterations;
}

Map<String, int> _coldEnglishLookup(_EnglishCase item, EnglishDialect dialect) {
  final rssBefore = ProcessInfo.currentRss;
  final stopwatch = Stopwatch()..start();
  final result = PinnedEnglishLexicon(
    dialect: dialect,
  ).lookup(item.token, const EnglishTokenContext());
  stopwatch.stop();
  if (result == null) {
    throw StateError('Cold English benchmark case produced no pronunciation.');
  }
  return <String, int>{
    'elapsedMicroseconds': stopwatch.elapsedMicroseconds,
    'rssDeltaBytes': ProcessInfo.currentRss - rssBefore,
  };
}

Map<String, num> _summarize(
  List<int> samples, {
  required int operationsPerSample,
}) {
  final sorted = samples.toList()..sort();
  final totalMicroseconds = samples.fold<int>(
    0,
    (total, value) => total + value,
  );
  final operationCount = samples.length * operationsPerSample;
  return <String, num>{
    'samples': samples.length,
    'operations': operationCount,
    'p50MicrosecondsPerSample': _percentile(sorted, 0.50),
    'p95MicrosecondsPerSample': _percentile(sorted, 0.95),
    'operationsPerSecond': totalMicroseconds == 0
        ? 0
        : operationCount * Duration.microsecondsPerSecond / totalMicroseconds,
  };
}

int _percentile(List<int> sorted, double percentile) {
  final index = (sorted.length * percentile).ceil() - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}

int _mix(int checksum, String value) {
  var result = checksum;
  for (final scalar in value.runes) {
    result = ((result * 31) ^ scalar) & 0x7fffffff;
  }
  return result;
}

final class _BenchmarkCorpus {
  _BenchmarkCorpus({
    required this.upstreamCommit,
    required this.english,
    required this.japaneseNumbers,
  });

  factory _BenchmarkCorpus.load(File file) {
    final root = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    if (root['schemaVersion'] != 1) {
      throw const FormatException('Unsupported benchmark corpus schema.');
    }
    final english = (root['english'] as List<Object?>)
        .map((value) => _EnglishCase.fromJson(value as Map<String, Object?>))
        .toList(growable: false);
    final japanese = (root['japaneseNumbers'] as List<Object?>)
        .cast<String>()
        .toList(growable: false);
    if (english.isEmpty || japanese.isEmpty) {
      throw const FormatException('Benchmark corpus groups must not be empty.');
    }
    return _BenchmarkCorpus(
      upstreamCommit: root['upstreamCommit']! as String,
      english: english,
      japaneseNumbers: japanese,
    );
  }

  final String upstreamCommit;
  final List<_EnglishCase> english;
  final List<String> japaneseNumbers;
}

final class _EnglishCase {
  const _EnglishCase({required this.text, required this.tag});

  factory _EnglishCase.fromJson(Map<String, Object?> json) =>
      _EnglishCase(text: json['text']! as String, tag: json['tag']! as String);

  final String text;
  final String tag;

  MisakiToken get token => MisakiToken(
    text: text,
    tag: tag,
    whitespace: '',
    metadata: const EnglishTokenMetadata(isHead: true),
  );
}
