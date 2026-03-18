//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

library openapi.api;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

part 'api_client.dart';
part 'api_helper.dart';
part 'api_exception.dart';
part 'auth/authentication.dart';
part 'auth/api_key_auth.dart';
part 'auth/oauth.dart';
part 'auth/http_basic_auth.dart';
part 'auth/http_bearer_auth.dart';

part 'api/file_api.dart';
part 'api/kv_api.dart';
part 'api/web_socket_api.dart';

part 'model/dev_ctr_hello_api_file_v1_file_delete_req.dart';
part 'model/dev_ctr_hello_api_file_v1_file_delete_res.dart';
part 'model/dev_ctr_hello_api_file_v1_file_download_req.dart';
part 'model/dev_ctr_hello_api_file_v1_file_metadata_req.dart';
part 'model/dev_ctr_hello_api_file_v1_file_metadata_res.dart';
part 'model/dev_ctr_hello_api_file_v1_file_upload_req.dart';
part 'model/dev_ctr_hello_api_file_v1_file_upload_res.dart';
part 'model/dev_ctr_hello_api_kv_v1_kv_delete_req.dart';
part 'model/dev_ctr_hello_api_kv_v1_kv_delete_res.dart';
part 'model/dev_ctr_hello_api_kv_v1_kv_get_req.dart';
part 'model/dev_ctr_hello_api_kv_v1_kv_get_res.dart';
part 'model/dev_ctr_hello_api_kv_v1_kv_item.dart';
part 'model/dev_ctr_hello_api_kv_v1_kv_list_req.dart';
part 'model/dev_ctr_hello_api_kv_v1_kv_list_res.dart';
part 'model/dev_ctr_hello_api_kv_v1_kv_set_req.dart';
part 'model/dev_ctr_hello_api_kv_v1_kv_set_res.dart';
part 'model/dev_ctr_hello_api_ws_v1_room_info.dart';
part 'model/dev_ctr_hello_api_ws_v1_ws_broadcast_req.dart';
part 'model/dev_ctr_hello_api_ws_v1_ws_broadcast_res.dart';
part 'model/dev_ctr_hello_api_ws_v1_ws_connect_req.dart';
part 'model/dev_ctr_hello_api_ws_v1_ws_connect_res.dart';
part 'model/dev_ctr_hello_api_ws_v1_ws_rooms_res.dart';
part 'model/dev_ctr_hello_api_ws_v1_ws_stats_res.dart';


/// An [ApiClient] instance that uses the default values obtained from
/// the OpenAPI specification file.
var defaultApiClient = ApiClient();

const _delimiters = {'csv': ',', 'ssv': ' ', 'tsv': '\t', 'pipes': '|'};
const _dateEpochMarker = 'epoch';
const _deepEquality = DeepCollectionEquality();
final _dateFormatter = DateFormat('yyyy-MM-dd');
final _regList = RegExp(r'^List<(.*)>$');
final _regSet = RegExp(r'^Set<(.*)>$');
final _regMap = RegExp(r'^Map<String,(.*)>$');

bool _isEpochMarker(String? pattern) => pattern == _dateEpochMarker || pattern == '/$_dateEpochMarker/';
