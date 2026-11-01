import 'package:dio/dio.dart';

import '../sync/retry_policy.dart';

/// One mutation as it goes over the wire. contracts/api.openapi.yaml.
class MutationPayload {
  const MutationPayload({
    required this.seq,
    required this.operation,
    required this.entityType,
    required this.id,
    required this.updatedAt,
    this.body,
  });

  final int seq;
  final String operation;
  final String entityType;
  final String id;
  final DateTime updatedAt;
  final Map<String, Object?>? body;

  Map<String, Object?> toJson() => {
        'seq': seq,
        'operation': operation,
        'entityType': entityType,
        'id': id,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (body != null) 'body': body,
      };
}

class MutationResult {
  const MutationResult({
    required this.outcome,
    required this.appliedCount,
    this.failedIndex,
    this.message,
  });

  final SyncOutcome outcome;
  final int appliedCount;

  /// Mutations before this index DID apply and must not be re-sent
  /// (contracts/sync-protocol.md, Normal drain).
  final int? failedIndex;
  final String? message;
}

class SnapshotPage {
  const SnapshotPage({
    required this.records,
    required this.hasMore,
    this.nextCursor,
  });

  final List<Map<String, Object?>> records;
  final bool hasMore;
  final String? nextCursor;
}

/// Talks to the sync API.
///
/// Note what this class never sends: an account id. FR-062 and
/// contracts/sync-protocol.md I5 put ownership entirely in the verified token, and
/// the server rejects a request that names an account. Keeping the client honest
/// here means a client bug surfaces as a 400 rather than as a silent cross-account
/// write.
class ApiClient {
  ApiClient({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<MutationResult> postMutations(List<MutationPayload> mutations) async {
    try {
      final response = await _dio.post<Map<String, Object?>>(
        '/v1/mutations',
        data: {'mutations': mutations.map((m) => m.toJson()).toList()},
      );
      final data = response.data ?? const {};
      final failedIndex = data['failedIndex'] as int?;
      return MutationResult(
        outcome: failedIndex == null ? SyncOutcome.applied : SyncOutcome.rejected,
        appliedCount: (data['appliedCount'] as int?) ?? 0,
        failedIndex: failedIndex,
        message: (data['error'] as Map<String, Object?>?)?['message'] as String?,
      );
    } on DioException catch (e) {
      return MutationResult(
        outcome: _classify(e),
        appliedCount: 0,
        message: e.message,
      );
    }
  }

  Future<SnapshotPage> getSnapshot({String? cursor, DateTime? since}) async {
    final response = await _dio.get<Map<String, Object?>>(
      '/v1/snapshot',
      queryParameters: {
        if (cursor != null) 'cursor': cursor,
        if (since != null) 'since': since.toUtc().toIso8601String(),
      },
    );
    final data = response.data ?? const {};
    return SnapshotPage(
      records: ((data['records'] as List?) ?? const [])
          .cast<Map<String, Object?>>(),
      hasMore: (data['hasMore'] as bool?) ?? false,
      nextCursor: data['nextCursor'] as String?,
    );
  }

  /// FR-026b, research.md R10. Unauthenticated, so a guest gets recommendations too.
  Future<Map<String, Object?>?> getReferenceData({int? since}) async {
    final response = await _dio.get<Map<String, Object?>>(
      '/v1/reference-data',
      queryParameters: {if (since != null) 'since': since},
      options: Options(
        validateStatus: (status) =>
            status == 200 || status == 204 || status == 304,
      ),
    );
    // 304: the local bundle is current. 204: this deployment publishes none at
    // all, so the bundle the app ships with stands. Nothing to apply either way.
    if (response.statusCode != 200) return null;
    return response.data;
  }

  SyncOutcome _classify(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        // No connectivity is not a failure — the farmer's save already succeeded
        // locally, and this entry simply waits (FR-053).
        return SyncOutcome.offline;
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode ?? 0;
        if (status == 401 || status == 403) return SyncOutcome.unauthorized;
        if (status >= 500) return SyncOutcome.retryable;
        return SyncOutcome.rejected;
      default:
        return SyncOutcome.retryable;
    }
  }
}
