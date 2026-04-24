#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_health.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_health'
  s.version          = '0.1.0'
  s.summary          = 'Internal plugin: Samsung Health + Apple HealthKit bridge.'
  s.description      = <<-DESC
Internal plugin bridging Samsung Health (Android) and Apple HealthKit (iOS)
with a schema identical to diaconn-aid-android/ios for server compatibility.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Diaconn' => 'diaconn@g2e.co.kr' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '18.0'

  s.frameworks = 'HealthKit'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # s.resource_bundles = {'flutter_health_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
