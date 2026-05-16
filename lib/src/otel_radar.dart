// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_radar_suppression.dart';

const _tracerName = 'dartastic_otel_libs_radar';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

class RadarResult {
  const RadarResult({
    this.eventCount,
    this.geofencesEnteredCount,
    this.placesMatchedCount,
    this.confidence,
    this.tripStatus,
    this.userId,
    this.requestId,
    this.statusCode,
  });

  /// Number of Radar events emitted by this call (entry / exit / dwell
  /// per geofence). Radar bills per event + per tracked user.
  final int? eventCount;

  /// Geofences entered in this `/v1/track` call.
  final int? geofencesEnteredCount;

  /// Places matched in a `/v1/search/places` call (cost dim for the
  /// Places product).
  final int? placesMatchedCount;

  /// Radar confidence band: `low` / `medium` / `high` / `exact`.
  final String? confidence;

  /// Trip lifecycle status: `started` / `approaching` / `arrived` /
  /// `completed` / `canceled`.
  final String? tripStatus;

  /// Radar `userId` (the tracked subject; cardinality-sensitive).
  final String? userId;

  /// `X-Radar-Request-Id`.
  final String? requestId;
  final int? statusCode;
}

class RadarCallResult<T> {
  const RadarCallResult({required this.value, this.result});
  final T value;
  final RadarResult? result;
}

/// Wraps a Radar REST call in a CLIENT span. [operation] should be one
/// of `track`, `geofences.list`, `geofences.upsert`, `search.places`,
/// `search.geocode`, `route.distance`, `route.matrix`, `trips.start`,
/// `trips.update`, `trips.complete`.
Future<T> tracedRadar<T>({
  required String operation,
  required Future<RadarCallResult<T>> Function() invoke,
  String? product,
  String? geofenceTag,
}) async {
  if (radarInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'rpc.system': 'radar',
    'rpc.method': operation,
    'radar.operation': operation,
  };
  if (product != null) m['radar.product'] = product;
  if (geofenceTag != null) m['radar.geofence.tag'] = geofenceTag;

  final span = _tracer().startSpan(
    'radar $operation',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    if (r.result != null) {
      final extras = <Attribute<Object>>[];
      if (r.result!.eventCount != null) {
        extras.add(OTel.attributeInt(
          'radar.event_count',
          r.result!.eventCount!,
        ));
      }
      if (r.result!.geofencesEnteredCount != null) {
        extras.add(OTel.attributeInt(
          'radar.geofences_entered_count',
          r.result!.geofencesEnteredCount!,
        ));
      }
      if (r.result!.placesMatchedCount != null) {
        extras.add(OTel.attributeInt(
          'radar.places_matched_count',
          r.result!.placesMatchedCount!,
        ));
      }
      if (r.result!.confidence != null) {
        extras.add(OTel.attributeString(
          'radar.confidence',
          r.result!.confidence!,
        ));
      }
      if (r.result!.tripStatus != null) {
        extras.add(OTel.attributeString(
          'radar.trip.status',
          r.result!.tripStatus!,
        ));
      }
      if (r.result!.userId != null) {
        extras.add(OTel.attributeString(
          'radar.user.id',
          r.result!.userId!,
        ));
      }
      if (r.result!.requestId != null) {
        extras.add(OTel.attributeString(
          'radar.request.id',
          r.result!.requestId!,
        ));
      }
      if (r.result!.statusCode != null) {
        extras.add(OTel.attributeInt(
          'http.response.status_code',
          r.result!.statusCode!,
        ));
        if (r.result!.statusCode! >= 400) {
          span.setStatus(
            SpanStatusCode.Error,
            'Radar HTTP ${r.result!.statusCode}',
          );
        }
      }
      if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    }
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
