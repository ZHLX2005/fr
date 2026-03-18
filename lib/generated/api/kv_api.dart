//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class KVApi {
  KVApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// List all KV
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [int] limit:
  ///
  /// * [int] offset:
  Future<Response> apiV1KvGetWithHttpInfo({ int? limit, int? offset, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/kv';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (limit != null) {
      queryParams.addAll(_queryParams('', 'limit', limit));
    }
    if (offset != null) {
      queryParams.addAll(_queryParams('', 'offset', offset));
    }

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
    );
  }

  /// List all KV
  ///
  /// Parameters:
  ///
  /// * [int] limit:
  ///
  /// * [int] offset:
  Future<DevCtrHelloApiKvV1KvListRes?> apiV1KvGet({ int? limit, int? offset, }) async {
    final response = await apiV1KvGetWithHttpInfo( limit: limit, offset: offset, );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DevCtrHelloApiKvV1KvListRes',) as DevCtrHelloApiKvV1KvListRes;
    
    }
    return null;
  }

  /// Delete KV
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] key:
  ///   Key
  Future<Response> apiV1KvKeyDeleteWithHttpInfo({ String? key, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/kv/:key';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    // Query parameter (as per API spec)
    if (key != null) {
      queryParams.addAll(_queryParams('', 'key', key));
    }

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'DELETE',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
    );
  }

  /// Delete KV
  ///
  /// Parameters:
  ///
  /// * [String] key:
  ///   Key
  Future<DevCtrHelloApiKvV1KvDeleteRes?> apiV1KvKeyDelete({ String? key, }) async {
    final response = await apiV1KvKeyDeleteWithHttpInfo( key: key, );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DevCtrHelloApiKvV1KvDeleteRes',) as DevCtrHelloApiKvV1KvDeleteRes;
    
    }
    return null;
  }

  /// Get KV
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] key:
  ///   Key
  Future<Response> apiV1KvKeyGetWithHttpInfo({ String? key, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/kv/:key';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    // Query parameter (as per API spec)
    if (key != null) {
      queryParams.addAll(_queryParams('', 'key', key));
    }

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
    );
  }

  /// Get KV
  ///
  /// Parameters:
  ///
  /// * [String] key:
  ///   Key
  Future<DevCtrHelloApiKvV1KvGetRes?> apiV1KvKeyGet({ String? key, }) async {
    final response = await apiV1KvKeyGetWithHttpInfo( key: key, );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DevCtrHelloApiKvV1KvGetRes',) as DevCtrHelloApiKvV1KvGetRes;
    
    }
    return null;
  }

  /// Set KV
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [DevCtrHelloApiKvV1KvSetReq] devCtrHelloApiKvV1KvSetReq (required):
  Future<Response> apiV1KvPostWithHttpInfo(DevCtrHelloApiKvV1KvSetReq devCtrHelloApiKvV1KvSetReq,) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/kv';

    // ignore: prefer_final_locals
    Object? postBody = devCtrHelloApiKvV1KvSetReq;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
    );
  }

  /// Set KV
  ///
  /// Parameters:
  ///
  /// * [DevCtrHelloApiKvV1KvSetReq] devCtrHelloApiKvV1KvSetReq (required):
  Future<DevCtrHelloApiKvV1KvSetRes?> apiV1KvPost(DevCtrHelloApiKvV1KvSetReq devCtrHelloApiKvV1KvSetReq,) async {
    final response = await apiV1KvPostWithHttpInfo(devCtrHelloApiKvV1KvSetReq,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DevCtrHelloApiKvV1KvSetRes',) as DevCtrHelloApiKvV1KvSetRes;
    
    }
    return null;
  }
}
