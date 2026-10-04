abstract final class BrandConfig {
  static const appName = 'HRMate';

  static const companyName = String.fromEnvironment(
    'HRMS_COMPANY_NAME',
    defaultValue: 'GD FOODS MFG. (I) PVT. LTD.',
  );

  static const companyShortName = String.fromEnvironment(
    'HRMS_COMPANY_SHORT_NAME',
    defaultValue: 'GD Foods',
  );
}
