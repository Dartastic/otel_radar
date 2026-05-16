// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_radar/otel_radar.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_radar-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('track records event_count + geofences_entered_count', () async {
    await tracedRadar<String>(
      operation: 'track',
      product: 'geofencing',
      invoke: () async => const RadarCallResult(
        value: 'ok',
        result: RadarResult(
          eventCount: 3,
          geofencesEnteredCount: 2,
          confidence: 'high',
          userId: 'u-1',
          statusCode: 200,
        ),
      ),
    );
    final a = attrsOf(spans.findSpanByName('radar track')!);
    expect(a['radar.operation'], 'track');
    expect(a['radar.product'], 'geofencing');
    expect(a['radar.event_count'], 3);
    expect(a['radar.geofences_entered_count'], 2);
    expect(a['radar.confidence'], 'high');
  });

  test('trip status surfaces on span', () async {
    await tracedRadar<String>(
      operation: 'trips.complete',
      invoke: () async => const RadarCallResult(
        value: 'ok',
        result: RadarResult(tripStatus: 'completed'),
      ),
    );
    final a = attrsOf(spans.findSpanByName('radar trips.complete')!);
    expect(a['radar.trip.status'], 'completed');
  });

  test('HTTP 4xx maps to span error', () async {
    await tracedRadar<String>(
      operation: 'search.places',
      invoke: () async => const RadarCallResult(
        value: 'ok',
        result: RadarResult(statusCode: 429),
      ),
    );
    expect(
      spans.findSpanByName('radar search.places')!.status,
      SpanStatusCode.Error,
    );
  });

  test('suppression skips spans', () async {
    await runWithoutRadarInstrumentationAsync(() async {
      await tracedRadar<String>(
        operation: 'track',
        invoke: () async => const RadarCallResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('radar '), isEmpty);
  });
}
