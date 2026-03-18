//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DevCtrHelloApiWsV1WsBroadcastRes {
  /// Returns a new [DevCtrHelloApiWsV1WsBroadcastRes] instance.
  DevCtrHelloApiWsV1WsBroadcastRes({
    this.status,
    this.message,
    this.room,
  });

  /// Status
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? status;

  /// Message content
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? message;

  /// Room ID
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? room;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DevCtrHelloApiWsV1WsBroadcastRes &&
    other.status == status &&
    other.message == message &&
    other.room == room;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (status == null ? 0 : status!.hashCode) +
    (message == null ? 0 : message!.hashCode) +
    (room == null ? 0 : room!.hashCode);

  @override
  String toString() => 'DevCtrHelloApiWsV1WsBroadcastRes[status=$status, message=$message, room=$room]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.status != null) {
      json[r'status'] = this.status;
    } else {
      json[r'status'] = null;
    }
    if (this.message != null) {
      json[r'message'] = this.message;
    } else {
      json[r'message'] = null;
    }
    if (this.room != null) {
      json[r'room'] = this.room;
    } else {
      json[r'room'] = null;
    }
    return json;
  }

  /// Returns a new [DevCtrHelloApiWsV1WsBroadcastRes] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DevCtrHelloApiWsV1WsBroadcastRes? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        requiredKeys.forEach((key) {
          assert(json.containsKey(key), 'Required key "DevCtrHelloApiWsV1WsBroadcastRes[$key]" is missing from JSON.');
          assert(json[key] != null, 'Required key "DevCtrHelloApiWsV1WsBroadcastRes[$key]" has a null value in JSON.');
        });
        return true;
      }());

      return DevCtrHelloApiWsV1WsBroadcastRes(
        status: mapValueOfType<String>(json, r'status'),
        message: mapValueOfType<String>(json, r'message'),
        room: mapValueOfType<String>(json, r'room'),
      );
    }
    return null;
  }

  static List<DevCtrHelloApiWsV1WsBroadcastRes> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DevCtrHelloApiWsV1WsBroadcastRes>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DevCtrHelloApiWsV1WsBroadcastRes.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DevCtrHelloApiWsV1WsBroadcastRes> mapFromJson(dynamic json) {
    final map = <String, DevCtrHelloApiWsV1WsBroadcastRes>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DevCtrHelloApiWsV1WsBroadcastRes.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DevCtrHelloApiWsV1WsBroadcastRes-objects as value to a dart map
  static Map<String, List<DevCtrHelloApiWsV1WsBroadcastRes>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DevCtrHelloApiWsV1WsBroadcastRes>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DevCtrHelloApiWsV1WsBroadcastRes.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

