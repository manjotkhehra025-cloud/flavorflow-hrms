import '../models/attendance.dart';

/// Hooks for location + selfie checks during punch in/out.
///
/// Everything here is a placeholder so the app works without permissions.
/// Next steps (see README):
///  * Location: add `geolocator`, request permission, return the real position.
///  * Geo-fence: compare with the office coordinates below.
///  * Selfie: add `image_picker` (or `camera`), capture a front-camera photo,
///    upload it to storage (e.g. Firebase Storage) and return its URL.
class PunchVerificationService {
  const PunchVerificationService();

  /// Office location and allowed radius (sample: Mohali). Change for your office.
  static const double officeLatitude = 30.7046;
  static const double officeLongitude = 76.7179;
  static const double allowedRadiusMeters = 200;

  /// TODO(geo): return the device's current GPS position.
  Future<PunchLocation?> getCurrentLocation() async => null;

  /// TODO(geo-fence): return false when [location] is farther than
  /// [allowedRadiusMeters] from the office (use Geolocator.distanceBetween).
  bool isInsideOffice(PunchLocation? location) => true;

  /// TODO(selfie): open the front camera, upload the photo, return its URL.
  Future<String?> captureSelfie() async => null;
}
