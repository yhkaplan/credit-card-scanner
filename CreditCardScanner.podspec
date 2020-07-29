Pod::Spec.new do |s|
  s.name             = 'CreditCardScanner'
  s.version          = '0.1.0'
  s.summary          = 'A library to scan credit card info using the device camera and on-device machine learning'
  s.homepage         = 'https://github.com/yhkaplan/credit-card-scanner'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2' TODO:
  s.license          = { :type => 'MIT', :file => 'LICENSE.md' }
  s.author           = { 'Joshua Kaplan' => 'yhkaplan@gmail.com' }
  s.source           = { :git => 'https://github.com/yhkaplan/credit-card-scanner.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/yhkaplan'
  s.ios.deployment_target = '13.0'
  s.swift_versions = ['5.1', '5.2', '5.3']
  s.dependency       = 'Reg', '~> 0.3.0' # TODO: Actually implement cococapods support
  s.dependency       = 'Sukar', '~> 0.1.0' # TODO: actually implement Cocoapods support
  s.static_framework = true
  s.source_files = 'Sources/**/*.{swift,h,m}'
end
