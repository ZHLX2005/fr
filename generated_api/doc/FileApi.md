# hello_api.api.FileApi

## Load the API package
```dart
import 'package:hello_api/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**apiV1DownloadIdGet**](FileApi.md#apiv1downloadidget) | **GET** /api/v1/download/:id | Download file
[**apiV1FileIdDelete**](FileApi.md#apiv1fileiddelete) | **DELETE** /api/v1/file/:id | Delete file
[**apiV1FileIdMetadataGet**](FileApi.md#apiv1fileidmetadataget) | **GET** /api/v1/file/:id/metadata | Get file metadata
[**apiV1UploadPost**](FileApi.md#apiv1uploadpost) | **POST** /api/v1/upload | Upload file


# **apiV1DownloadIdGet**
> Object apiV1DownloadIdGet(id)

Download file

### Example
```dart
import 'package:hello_api/api.dart';

final api_instance = FileApi();
final id = id_example; // String | File ID

try {
    final result = api_instance.apiV1DownloadIdGet(id);
    print(result);
} catch (e) {
    print('Exception when calling FileApi->apiV1DownloadIdGet: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**| File ID | [optional] 

### Return type

[**Object**](Object.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **apiV1FileIdDelete**
> DevCtrHelloApiFileV1FileDeleteRes apiV1FileIdDelete(id)

Delete file

### Example
```dart
import 'package:hello_api/api.dart';

final api_instance = FileApi();
final id = id_example; // String | File ID

try {
    final result = api_instance.apiV1FileIdDelete(id);
    print(result);
} catch (e) {
    print('Exception when calling FileApi->apiV1FileIdDelete: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**| File ID | [optional] 

### Return type

[**DevCtrHelloApiFileV1FileDeleteRes**](DevCtrHelloApiFileV1FileDeleteRes.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **apiV1FileIdMetadataGet**
> DevCtrHelloApiFileV1FileMetadataRes apiV1FileIdMetadataGet(id)

Get file metadata

### Example
```dart
import 'package:hello_api/api.dart';

final api_instance = FileApi();
final id = id_example; // String | File ID

try {
    final result = api_instance.apiV1FileIdMetadataGet(id);
    print(result);
} catch (e) {
    print('Exception when calling FileApi->apiV1FileIdMetadataGet: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**| File ID | [optional] 

### Return type

[**DevCtrHelloApiFileV1FileMetadataRes**](DevCtrHelloApiFileV1FileMetadataRes.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **apiV1UploadPost**
> DevCtrHelloApiFileV1FileUploadRes apiV1UploadPost(devCtrHelloApiFileV1FileUploadReq)

Upload file

### Example
```dart
import 'package:hello_api/api.dart';

final api_instance = FileApi();
final devCtrHelloApiFileV1FileUploadReq = DevCtrHelloApiFileV1FileUploadReq(); // DevCtrHelloApiFileV1FileUploadReq | 

try {
    final result = api_instance.apiV1UploadPost(devCtrHelloApiFileV1FileUploadReq);
    print(result);
} catch (e) {
    print('Exception when calling FileApi->apiV1UploadPost: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **devCtrHelloApiFileV1FileUploadReq** | [**DevCtrHelloApiFileV1FileUploadReq**](DevCtrHelloApiFileV1FileUploadReq.md)|  | 

### Return type

[**DevCtrHelloApiFileV1FileUploadRes**](DevCtrHelloApiFileV1FileUploadRes.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

