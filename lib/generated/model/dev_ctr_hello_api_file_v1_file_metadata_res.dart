//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DevCtrHelloApiFileV1FileMetadataRes {
  /// Returns a new [DevCtrHelloApiFileV1FileMetadataRes] instance.
  DevCtrHelloApiFileV1FileMetadataRes({
    this.id,
    this.name,
    this.size,
    this.contentType,
    this.uploadTime,
    this.expiresAt,
  });

  /// File ID
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? id;

  /// File name
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? name;

  /// File size
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? size;

  /// Content type
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? contentType;

  /// Upload time
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? uploadTime;

  /// Expiration time
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? expiresAt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DevCtrHelloApiFileV1FileMetadataRes &&
    other.id == id &&
    other.name == name &&
    other.size == size &&
    other.contentType == contentType &&
    other.uploadTime == uploadTime &&
    other.expiresAt == expiresAt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id == null ? 0 : id!.hashCode) +
    (name == null ? 0 : name!.hashCode) +
    (size == null ? 0 : size!.hashCode) +
    (contentType == null ? 0 : contentType!.hashCode) +
    (uploadTime == null ? 0 : uploadTime!.hashCode) +
    (expiresAt == null ? 0 : expiresAt!.hashCode);

  @override
  String toString() => 'DevCtrHelloApiFileV1FileMetadataRes[id=$id, name=$name, size=$size, contentType=$contentType, uploadTime=$uploadTime, expiresAt=$expiresAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.id != null) {
      json[r'id'] = this.id;
    } else {
      json[r'id'] = null;
    }
    if (this.name != null) {
      json[r'name'] = this.name;
    } else {
      json[r'name'] = null;
    }
    if (this.size != null) {
      json[r'size'] = this.size;
    } else {
      json[r'size'] = null;
    }
    if (this.contentType != null) {
      json[r'content_type'] = this.contentType;
    } else {
      json[r'content_type'] = null;
    }
    if (this.uploadTime != null) {
      json[r'upload_time'] = this.uploadTime;
    } else {
      json[r'upload_time'] = null;
    }
    if (this.expiresAt != null) {
      json[r'expires_at'] = this.expiresAt;
    } else {
      json[r'expires_at'] = null;
    }
    return json;
  }

  /// Returns a new [DevCtrHelloApiFileV1FileMetadataRes] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DevCtrHelloApiFileV1FileMetadataRes? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        requiredKeys.forEach((key) {
          assert(json.containsKey(key), 'Required key "DevCtrHelloApiFileV1FileMetadataRes[$key]" is missing from JSON.');
          assert(json[key] != null, 'Required key "DevCtrHelloApiFileV1FileMetadataRes[$key]" has a null value in JSON.');
        });
        return true;
      }());

      return DevCtrHelloApiFileV1FileMetadataRes(
        id: mapValueOfType<String>(json, r'id'),
        name: mapValueOfType<String>(json, r'name'),
        size: mapValueOfType<int>(json, r'size'),
        contentType: mapValueOfType<String>(json, r'content_type'),
        uploadTime: mapValueOfType<String>(json, r'upload_time'),
        expiresAt: mapValueOfType<String>(json, r'expires_at'),
      );
    }
    return null;
  }

  static List<DevCtrHelloApiFileV1FileMetadataRes> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DevCtrHelloApiFileV1FileMetadataRes>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DevCtrHelloApiFileV1FileMetadataRes.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DevCtrHelloApiFileV1FileMetadataRes> mapFromJson(dynamic json) {
    final map = <String, DevCtrHelloApiFileV1FileMetadataRes>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DevCtrHelloApiFileV1FileMetadataRes.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DevCtrHelloApiFileV1FileMetadataRes-objects as value to a dart map
  static Map<String, List<DevCtrHelloApiFileV1FileMetadataRes>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DevCtrHelloApiFileV1FileMetadataRes>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DevCtrHelloApiFileV1FileMetadataRes.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

