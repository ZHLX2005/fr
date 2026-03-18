//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class WebSocketApi {
  WebSocketApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Broadcast message
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [DevCtrHelloApiWsV1WsBroadcastReq] devCtrHelloApiWsV1WsBroadcastReq (required):
  Future<Response> apiV1WsBroadcastPostWithHttpInfo(DevCtrHelloApiWsV1WsBroadcastReq devCtrHelloApiWsV1WsBroadcastReq,) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/ws/broadcast';

    // ignore: prefer_final_locals
    Object? postBody = devCtrHelloApiWsV1WsBroadcastReq;

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

  /// Broadcast message
  ///
  /// Parameters:
  ///
  /// * [DevCtrHelloApiWsV1WsBroadcastReq] devCtrHelloApiWsV1WsBroadcastReq (required):
  Future<DevCtrHelloApiWsV1WsBroadcastRes?> apiV1WsBroadcastPost(DevCtrHelloApiWsV1WsBroadcastReq devCtrHelloApiWsV1WsBroadcastReq,) async {
    final response = await apiV1WsBroadcastPostWithHttpInfo(devCtrHelloApiWsV1WsBroadcastReq,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DevCtrHelloApiWsV1WsBroadcastRes',) as DevCtrHelloApiWsV1WsBroadcastRes;
    
    }
    return null;
  }

  /// WebSocket connection
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] token:
  ///   WebSocket connection token
  Future<Response> apiV1WsGetWithHttpInfo({ String? token, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/ws';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (token != null) {
      queryParams.addAll(_queryParams('', 'token', token));
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

  /// WebSocket connection
  ///
  /// Parameters:
  ///
  /// * [String] token:
  ///   WebSocket connection token
  Future<DevCtrHelloApiWsV1WsConnectRes?> apiV1WsGet({ String? token, }) async {
    final response = await apiV1WsGetWithHttpInfo( token: token, );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DevCtrHelloApiWsV1WsConnectRes',) as DevCtrHelloApiWsV1WsConnectRes;
    
    }
    return null;
  }

  /// Get room stats
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> apiV1WsRoomsGetWithHttpInfo() async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/ws/rooms';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

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

  /// Get room stats
  Future<DevCtrHelloApiWsV1WsRoomsRes?> apiV1WsRoomsGet() async {
    final response = await apiV1WsRoomsGetWithHttpInfo();
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DevCtrHelloApiWsV1WsRoomsRes',) as DevCtrHelloApiWsV1WsRoomsRes;
    
    }
    return null;
  }

  /// Get WebSocket stats
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> apiV1WsStatsGetWithHttpInfo() async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/ws/stats';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

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

  /// Get WebSocket stats
  Future<DevCtrHelloApiWsV1WsStatsRes?> apiV1WsStatsGet() async {
    final response = await apiV1WsStatsGetWithHttpInfo();
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DevCtrHelloApiWsV1WsStatsRes',) as DevCtrHelloApiWsV1WsStatsRes;
    
    }
    return null;
  }
}
