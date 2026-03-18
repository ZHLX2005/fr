# hello_api.api.KVApi

## Load the API package
```dart
import 'package:hello_api/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**apiV1KvGet**](KVApi.md#apiv1kvget) | **GET** /api/v1/kv | List all KV
[**apiV1KvKeyDelete**](KVApi.md#apiv1kvkeydelete) | **DELETE** /api/v1/kv/:key | Delete KV
[**apiV1KvKeyGet**](KVApi.md#apiv1kvkeyget) | **GET** /api/v1/kv/:key | Get KV
[**apiV1KvPost**](KVApi.md#apiv1kvpost) | **POST** /api/v1/kv | Set KV


# **apiV1KvGet**
> DevCtrHelloApiKvV1KvListRes apiV1KvGet(limit, offset)

List all KV

### Example
```dart
import 'package:hello_api/api.dart';

final api_instance = KVApi();
final limit = 789; // int | 
final offset = 789; // int | 

try {
    final result = api_instance.apiV1KvGet(limit, offset);
    print(result);
} catch (e) {
    print('Exception when calling KVApi->apiV1KvGet: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **limit** | **int**|  | [optional] 
 **offset** | **int**|  | [optional] 

### Return type

[**DevCtrHelloApiKvV1KvListRes**](DevCtrHelloApiKvV1KvListRes.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **apiV1KvKeyDelete**
> DevCtrHelloApiKvV1KvDeleteRes apiV1KvKeyDelete(key)

Delete KV

### Example
```dart
import 'package:hello_api/api.dart';

final api_instance = KVApi();
final key = key_example; // String | Key

try {
    final result = api_instance.apiV1KvKeyDelete(key);
    print(result);
} catch (e) {
    print('Exception when calling KVApi->apiV1KvKeyDelete: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **key** | **String**| Key | [optional] 

### Return type

[**DevCtrHelloApiKvV1KvDeleteRes**](DevCtrHelloApiKvV1KvDeleteRes.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **apiV1KvKeyGet**
> DevCtrHelloApiKvV1KvGetRes apiV1KvKeyGet(key)

Get KV

### Example
```dart
import 'package:hello_api/api.dart';

final api_instance = KVApi();
final key = key_example; // String | Key

try {
    final result = api_instance.apiV1KvKeyGet(key);
    print(result);
} catch (e) {
    print('Exception when calling KVApi->apiV1KvKeyGet: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **key** | **String**| Key | [optional] 

### Return type

[**DevCtrHelloApiKvV1KvGetRes**](DevCtrHelloApiKvV1KvGetRes.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **apiV1KvPost**
> DevCtrHelloApiKvV1KvSetRes apiV1KvPost(devCtrHelloApiKvV1KvSetReq)

Set KV

### Example
```dart
import 'package:hello_api/api.dart';

final api_instance = KVApi();
final devCtrHelloApiKvV1KvSetReq = DevCtrHelloApiKvV1KvSetReq(); // DevCtrHelloApiKvV1KvSetReq | 

try {
    final result = api_instance.apiV1KvPost(devCtrHelloApiKvV1KvSetReq);
    print(result);
} catch (e) {
    print('Exception when calling KVApi->apiV1KvPost: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **devCtrHelloApiKvV1KvSetReq** | [**DevCtrHelloApiKvV1KvSetReq**](DevCtrHelloApiKvV1KvSetReq.md)|  | 

### Return type

[**DevCtrHelloApiKvV1KvSetRes**](DevCtrHelloApiKvV1KvSetRes.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

