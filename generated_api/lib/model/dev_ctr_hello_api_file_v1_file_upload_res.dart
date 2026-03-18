//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class DevCtrHelloApiFileV1FileUploadRes {
  /// Returns a new [DevCtrHelloApiFileV1FileUploadRes] instance.
  DevCtrHelloApiFileV1FileUploadRes({
    this.id,
    this.name,
    this.size,
    this.contentType,
    this.extension_,
    this.uploadTime,
    this.expiresAt,
    this.downloadUrl,
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

  /// File extension
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? extension_;

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

  /// Download URL
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? downloadUrl;

  @override
  bool operator ==(Object other) => identical(this, other) || other is DevCtrHelloApiFileV1FileUploadRes &&
    other.id == id &&
    other.name == name &&
    other.size == size &&
    other.contentType == contentType &&
    other.extension_ == extension_ &&
    other.uploadTime == uploadTime &&
    other.expiresAt == expiresAt &&
    other.downloadUrl == downloadUrl;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id == null ? 0 : id!.hashCode) +
    (name == null ? 0 : name!.hashCode) +
    (size == null ? 0 : size!.hashCode) +
    (contentType == null ? 0 : contentType!.hashCode) +
    (extension_ == null ? 0 : extension_!.hashCode) +
    (uploadTime == null ? 0 : uploadTime!.hashCode) +
    (expiresAt == null ? 0 : expiresAt!.hashCode) +
    (downloadUrl == null ? 0 : downloadUrl!.hashCode);

  @override
  String toString() => 'DevCtrHelloApiFileV1FileUploadRes[id=$id, name=$name, size=$size, contentType=$contentType, extension_=$extension_, uploadTime=$uploadTime, expiresAt=$expiresAt, downloadUrl=$downloadUrl]';

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
    if (this.extension_ != null) {
      json[r'extension'] = this.extension_;
    } else {
      json[r'extension'] = null;
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
    if (this.downloadUrl != null) {
      json[r'download_url'] = this.downloadUrl;
    } else {
      json[r'download_url'] = null;
    }
    return json;
  }

  /// Returns a new [DevCtrHelloApiFileV1FileUploadRes] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DevCtrHelloApiFileV1FileUploadRes? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        requiredKeys.forEach((key) {
          assert(json.containsKey(key), 'Required key "DevCtrHelloApiFileV1FileUploadRes[$key]" is missing from JSON.');
          assert(json[key] != null, 'Required key "DevCtrHelloApiFileV1FileUploadRes[$key]" has a null value in JSON.');
        });
        return true;
      }());

      return DevCtrHelloApiFileV1FileUploadRes(
        id: mapValueOfType<String>(json, r'id'),
        name: mapValueOfType<String>(json, r'name'),
        size: mapValueOfType<int>(json, r'size'),
        contentType: mapValueOfType<String>(json, r'content_type'),
        extension_: mapValueOfType<String>(json, r'extension'),
        uploadTime: mapValueOfType<String>(json, r'upload_time'),
        expiresAt: mapValueOfType<String>(json, r'expires_at'),
        downloadUrl: mapValueOfType<String>(json, r'download_url'),
      );
    }
    return null;
  }

  static List<DevCtrHelloApiFileV1FileUploadRes> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <DevCtrHelloApiFileV1FileUploadRes>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DevCtrHelloApiFileV1FileUploadRes.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DevCtrHelloApiFileV1FileUploadRes> mapFromJson(dynamic json) {
    final map = <String, DevCtrHelloApiFileV1FileUploadRes>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DevCtrHelloApiFileV1FileUploadRes.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DevCtrHelloApiFileV1FileUploadRes-objects as value to a dart map
  static Map<String, List<DevCtrHelloApiFileV1FileUploadRes>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<DevCtrHelloApiFileV1FileUploadRes>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DevCtrHelloApiFileV1FileUploadRes.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

