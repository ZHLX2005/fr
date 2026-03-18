//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DevCtrHelloApiKvV1KvListReq {
  /// Returns a new [DevCtrHelloApiKvV1KvListReq] instance.
  DevCtrHelloApiKvV1KvListReq({
    this.limit,
    this.offset,
  });

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? limit;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? offset;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DevCtrHelloApiKvV1KvListReq &&
    other.limit == limit &&
    other.offset == offset;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (limit == null ? 0 : limit!.hashCode) +
    (offset == null ? 0 : offset!.hashCode);

  @override
  String toString() => 'DevCtrHelloApiKvV1KvListReq[limit=$limit, offset=$offset]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.limit != null) {
      json[r'limit'] = this.limit;
    } else {
      json[r'limit'] = null;
    }
    if (this.offset != null) {
      json[r'offset'] = this.offset;
    } else {
      json[r'offset'] = null;
    }
    return json;
  }

  /// Returns a new [DevCtrHelloApiKvV1KvListReq] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DevCtrHelloApiKvV1KvListReq? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        requiredKeys.forEach((key) {
          assert(json.containsKey(key), 'Required key "DevCtrHelloApiKvV1KvListReq[$key]" is missing from JSON.');
          assert(json[key] != null, 'Required key "DevCtrHelloApiKvV1KvListReq[$key]" has a null value in JSON.');
        });
        return true;
      }());

      return DevCtrHelloApiKvV1KvListReq(
        limit: mapValueOfType<int>(json, r'limit'),
        offset: mapValueOfType<int>(json, r'offset'),
      );
    }
    return null;
  }

  static List<DevCtrHelloApiKvV1KvListReq> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DevCtrHelloApiKvV1KvListReq>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DevCtrHelloApiKvV1KvListReq.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DevCtrHelloApiKvV1KvListReq> mapFromJson(dynamic json) {
    final map = <String, DevCtrHelloApiKvV1KvListReq>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DevCtrHelloApiKvV1KvListReq.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DevCtrHelloApiKvV1KvListReq-objects as value to a dart map
  static Map<String, List<DevCtrHelloApiKvV1KvListReq>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DevCtrHelloApiKvV1KvListReq>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DevCtrHelloApiKvV1KvListReq.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

