Pod::Spec.new do |s|
  s.name             = 'ios_camera_pro'
  s.version          = '0.1.0'
  s.summary          = 'Flutter iOS camera plugin with anti-macro, flash, zoom, and more.'
  s.description      = <<-DESC
    Comprehensive Flutter iOS camera plugin featuring:
    - Anti-macro camera (prevents auto-switch to ultra-wide/macro lens on iPhone 13 Pro+)
    - Flash control (off / auto / on / torch)
    - Torch with adjustable brightness level
    - Optical zoom control
    - Tap-to-focus and tap-to-expose
    - Exposure compensation (EV)
    - Photo capture (JPEG)
    - Video recording (MP4)
    - Front / back camera switching
  DESC

  s.homepage         = 'https://github.com/your-repo/ios_camera_pro'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Name' => 'your@email.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  s.dependency 'Flutter'
  s.platform     = :ios, '14.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_VERSION'  => '5.0',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }

  s.swift_version = '5.0'
end
