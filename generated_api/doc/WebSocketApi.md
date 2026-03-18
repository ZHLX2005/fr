# hello_api.api.WebSocketApi

## Load the API package
```dart
import 'package:hello_api/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**apiV1WsBroadcastPost**](WebSocketApi.md#apiv1wsbroadcastpost) | **POST** /api/v1/ws/broadcast | Broadcast message
[**apiV1WsGet**](WebSocketApi.md#apiv1wsget) | **GET** /api/v1/ws | WebSocket connection
[**apiV1WsRoomsGet**](WebSocketApi.md#apiv1wsroomsget) | **GET** /api/v1/ws/rooms | Get room stats
[**apiV1WsStatsGet**](WebSocketApi.md#apiv1wsstatsget) | **GET** /api/v1/ws/stats | Get WebSocket stats


# **apiV1WsBroadcastPost**
> DevCtrHelloApiWsV1WsBroadcastRes apiV1WsBroadcastPost(devCtrHelloApiWsV1WsBroadcastReq)

Broadcast message

### Example
```dart
import 'package:hello_api/api.dart';

final api_instance = WebSocketApi();
final devCtrHelloApiWsV1WsBroadcastReq = DevCtrHelloApiWsV1WsBroadcastReq(); // DevCtrHelloApiWsV1WsBroadcastReq | 

try {
    final result = api_instance.apiV1WsBroadcastPost(devCtrHelloApiWsV1WsBroadcastReq);
    print(result);
} catch (e) {
    print('Exception when calling WebSocketApi->apiV1WsBroadcastPost: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **devCtrHelloApiWsV1WsBroadcastReq** | [**DevCtrHelloApiWsV1WsBroadcastReq**](DevCtrHelloApiWsV1WsBroadcastReq.md)|  | 

### Return type

[**DevCtrHelloApiWsV1WsBroadcastRes**](DevCtrHelloApiWsV1WsBroadcastRes.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **apiV1WsGet**
> DevCtrHelloApiWsV1WsConnectRes apiV1WsGet(token)

WebSocket connection

### Example
```dart
import 'package:hello_api/api.dart';

final api_instance = WebSocketApi();
final token = token_example; // String | WebSocket connection token

try {
    final result = api_instance.apiV1WsGet(token);
    print(result);
} catch (e) {
    print('Exception when calling WebSocketApi->apiV1WsGet: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **token** | **String**| WebSocket connection token | [optional] 

### Return type

[**DevCtrHelloApiWsV1WsConnectRes**](DevCtrHelloApiWsV1WsConnectRes.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **apiV1WsRoomsGet**
> DevCtrHelloApiWsV1WsRoomsRes apiV1WsRoomsGet()

Get room stats

### Example
```dart
import 'package:hello_api/api.dart';

final api_instance = WebSocketApi();

try {
    final result = api_instance.apiV1WsRoomsGet();
    print(result);
} catch (e) {
    print('Exception when calling WebSocketApi->apiV1WsRoomsGet: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**DevCtrHelloApiWsV1WsRoomsRes**](DevCtrHelloApiWsV1WsRoomsRes.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **apiV1WsStatsGet**
> DevCtrHelloApiWsV1WsStatsRes apiV1WsStatsGet()

Get WebSocket stats

### Example
```dart
import 'package:hello_api/api.dart';

final api_instance = WebSocketApi();

try {
    final result = api_instance.apiV1WsStatsGet();
    print(result);
} catch (e) {
    print('Exception when calling WebSocketApi->apiV1WsStatsGet: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**DevCtrHelloApiWsV1WsStatsRes**](DevCtrHelloApiWsV1WsStatsRes.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

