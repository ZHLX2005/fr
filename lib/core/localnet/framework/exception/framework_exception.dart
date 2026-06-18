/// 框架异常基类
class FrameworkException implements Exception {
  const FrameworkException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => 'FrameworkException: $message${cause != null ? ' ($cause)' : ''}';
}

class FrameworkStartException extends FrameworkException {
  const FrameworkStartException(super.message, [super.cause]);
}

class FrameworkNotRunningException extends FrameworkException {
  const FrameworkNotRunningException(super.message);
}

class DeviceNotFoundException extends FrameworkException {
  const DeviceNotFoundException(super.message);
}
