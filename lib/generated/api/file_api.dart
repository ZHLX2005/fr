//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class FileApi {
  FileApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Download file
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] id:
  ///   File ID
  Future<Response> apiV1DownloadIdGetWithHttpInfo({ String? id, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/download/:id';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    // Query parameter (as per API spec)
    if (id != null) {
      queryParams.addAll(_queryParams('', 'id', id));
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

  /// Download file
  ///
  /// Parameters:
  ///
  /// * [String] id:
  ///   File ID
  Future<Object?> apiV1DownloadIdGet({ String? id, }) async {
    final response = await apiV1DownloadIdGetWithHttpInfo( id: id, );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Object',) as Object;
    
    }
    return null;
  }

  /// Delete file
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] id:
  ///   File ID
  Future<Response> apiV1FileIdDeleteWithHttpInfo({ String? id, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/file/:id';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    // Query parameter (as per API spec)
    if (id != null) {
      queryParams.addAll(_queryParams('', 'id', id));
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

  /// Delete file
  ///
  /// Parameters:
  ///
  /// * [String] id:
  ///   File ID
  Future<DevCtrHelloApiFileV1FileDeleteRes?> apiV1FileIdDelete({ String? id, }) async {
    final response = await apiV1FileIdDeleteWithHttpInfo( id: id, );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DevCtrHelloApiFileV1FileDeleteRes',) as DevCtrHelloApiFileV1FileDeleteRes;
    
    }
    return null;
  }

  /// Get file metadata
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] id:
  ///   File ID
  Future<Response> apiV1FileIdMetadataGetWithHttpInfo({ String? id, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/file/:id/metadata';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    // Query parameter (as per API spec)
    if (id != null) {
      queryParams.addAll(_queryParams('', 'id', id));
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

  /// Get file metadata
  ///
  /// Parameters:
  ///
  /// * [String] id:
  ///   File ID
  Future<DevCtrHelloApiFileV1FileMetadataRes?> apiV1FileIdMetadataGet({ String? id, }) async {
    final response = await apiV1FileIdMetadataGetWithHttpInfo( id: id, );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DevCtrHelloApiFileV1FileMetadataRes',) as DevCtrHelloApiFileV1FileMetadataRes;
    
    }
    return null;
  }

  /// Upload file
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [DevCtrHelloApiFileV1FileUploadReq] devCtrHelloApiFileV1FileUploadReq (required):
  Future<Response> apiV1UploadPostWithHttpInfo(DevCtrHelloApiFileV1FileUploadReq devCtrHelloApiFileV1FileUploadReq,) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/upload';

    // ignore: prefer_final_locals
    Object? postBody = devCtrHelloApiFileV1FileUploadReq;

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

  /// Upload file
  ///
  /// Parameters:
  ///
  /// * [DevCtrHelloApiFileV1FileUploadReq] devCtrHelloApiFileV1FileUploadReq (required):
  Future<DevCtrHelloApiFileV1FileUploadRes?> apiV1UploadPost(DevCtrHelloApiFileV1FileUploadReq devCtrHelloApiFileV1FileUploadReq,) async {
    final response = await apiV1UploadPostWithHttpInfo(devCtrHelloApiFileV1FileUploadReq,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DevCtrHelloApiFileV1FileUploadRes',) as DevCtrHelloApiFileV1FileUploadRes;
    
    }
    return null;
  }
}
