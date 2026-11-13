source 'https://github.com/CocoaPods/Specs.git'

minVersion = '12.0'

platform :osx, minVersion

# cocoapods-prune-localizations doesn't appear to auto-detect pods properly, so using a manual list
supported_locales = ['Base', 'da', 'de', 'en', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt-BR', 'sv', 'tr', 'zh-Hans']
plugin 'cocoapods-prune-localizations', { :localizations => supported_locales }

target "SelfControl" do
    use_frameworks! :linkage => :static
    pod 'MASPreferences', '~> 1.1.4'
    pod 'FormatterKit/TimeIntervalFormatter', '~> 1.8.0'
    pod 'LetsMove', '~> 1.24'
    
    # Add test target
    target 'SelfControlTests' do
        inherit! :complete
    end
end

target "SelfControl Killer" do
    use_frameworks! :linkage => :static
end

# Sentry was removed: crash reporting is disabled in this fork, and Sentry 7.x no longer
# compiles with current Xcode. These targets have no pods but stay listed so CocoaPods
# keeps managing their build settings. SCSentry compiles to no-ops without the pod.
target "SCKillerHelper" do
end
target "selfcontrol-cli" do
end
target "org.eyebeam.selfcontrold" do
end

post_install do |pi|
   # CocoaPods' resource-copy script expects static frameworks to have iOS-style flat resources
   # (Foo.framework/en.lproj/...), but macOS frameworks keep them under Foo.framework/Resources/.
   Dir.glob('Pods/Target Support Files/*/*-resources.sh').each do |script|
       src = File.read(script)
       fixed = src.gsub(%r{\.framework/(?!Resources/|Versions/)([^"/]+\.lproj/)}, '.framework/Resources/\1')
       File.write(script, fixed) if fixed != src
   end

   pi.pods_project.targets.each do |t|
       t.build_configurations.each do |bc|
           if Gem::Version.new(bc.build_settings['MACOSX_DEPLOYMENT_TARGET']) < Gem::Version.new(minVersion)
#            if bc.build_settings['MACOSX_DEPLOYMENT_TARGET'] == '8.0'
               bc.build_settings['MACOSX_DEPLOYMENT_TARGET'] = minVersion
           end
       end
   end
end
