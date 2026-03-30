Pod::Spec.new do |s|
  s.name         = 'MoneiPaySDK'
  s.version      = '0.2.0'
  s.summary      = 'Accept NFC tap-to-pay payments via MONEI Pay'
  s.homepage     = 'https://github.com/MONEI/monei-pay-ios-sdk'
  s.license      = { type: 'MIT', file: 'LICENSE' }
  s.author       = { 'MONEI' => 'admin@monei.com' }
  s.source       = { git: 'https://github.com/MONEI/monei-pay-ios-sdk.git', tag: "v#{s.version}" }
  s.ios.deployment_target = '15.0'
  s.swift_version = '5.9'
  s.source_files = 'Sources/MoneiPaySDK/**/*.swift'
end
