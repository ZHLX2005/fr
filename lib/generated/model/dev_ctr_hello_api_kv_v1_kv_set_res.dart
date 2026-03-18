//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DevCtrHelloApiKvV1KvSetRes {
  /// Returns a new [DevCtrHelloApiKvV1KvSetRes] instance.
  DevCtrHelloApiKvV1KvSetRes({
    this.message,
  });

  /// Message
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? message;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DevCtrHelloApiKvV1KvSetRes &&
    other.message == message;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (message == null ? 0 : message!.hashCode);

  @override
  String toString() => 'DevCtrHelloApiKvV1KvSetRes[message=$message]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.message != null) {
      json[r'message'] = this.message;
    } else {
      json[r'message'] = null;
    }
    return json;
  }

  /// Returns a new [DevCtrHelloApiKvV1KvSetRes] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DevCtrHelloApiKvV1KvSetRes? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        requiredKeys.forEach((key) {
          assert(json.containsKey(key), 'Required key "DevCtrHelloApiKvV1KvSetRes[$key]" is missing from JSON.');
          assert(json[key] != null, 'Required key "DevCtrHelloApiKvV1KvSetRes[$key]" has a null value in JSON.');
        });
        return true;
      }());

      return DevCtrHelloApiKvV1KvSetRes(
        message: mapValueOfType<String>(json, r'message'),
      );
    }
    return null;
  }

  static List<DevCtrHelloApiKvV1KvSetRes> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DevCtrHelloApiKvV1KvSetRes>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DevCtrHelloApiKvV1KvSetRes.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DevCtrHelloApiKvV1KvSetRes> mapFromJson(dynamic json) {
    final map = <String, DevCtrHelloApiKvV1KvSetRes>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DevCtrHelloApiKvV1KvSetRes.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DevCtrHelloApiKvV1KvSetRes-objects as value to a dart map
  static Map<String, List<DevCtrHelloApiKvV1KvSetRes>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DevCtrHelloApiKvV1KvSetRes>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DevCtrHelloApiKvV1KvSetRes.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

