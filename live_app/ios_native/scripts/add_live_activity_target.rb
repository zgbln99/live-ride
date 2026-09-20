#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds the Live Ride widget extension to the generated Xcode project.
#
# `flutter create` produces a single-target project, and a Live Activity needs
# a WidgetKit app-extension target embedded in the app. Doing that by hand in
# Xcode is six screens of clicking that has to be repeated every time the iOS
# shell is regenerated, so it is scripted here with the `xcodeproj` gem that
# ships with CocoaPods.
#
# The script is idempotent: running it again replaces the target rather than
# adding a second one.
#
# Usage: ruby add_live_activity_target.rb <path-to-ios-dir> <app-bundle-id>
#        ruby add_live_activity_target.rb <path-to-ios-dir> --order-only
#
# `--order-only` skips the target surgery and just re-applies the build-phase
# order. Run it if `pod install` or an Xcode upgrade ever reintroduces the
# "Cycle inside Runner" error.

require 'xcodeproj'
require 'fileutils'

ios_dir = ARGV[0] || 'ios'
order_only = ARGV.include?('--order-only')
app_bundle_id = ARGV.reject { |arg| arg.start_with?('--') }[1] ||
                'pl.marekpiatak.liveride'

TARGET_NAME = 'LiveRideWidgets'
DEPLOYMENT_TARGET = '16.2'

project_path = File.join(ios_dir, 'Runner.xcodeproj')
abort "No Xcode project at #{project_path}" unless Dir.exist?(project_path)

project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |target| target.name == 'Runner' }
abort 'No Runner target in the project' if runner.nil?

# ---------------------------------------------------------------- clean slate
unless order_only
existing = project.targets.select { |target| target.name == TARGET_NAME }
existing.each do |target|
  target.build_phases.each { |phase| phase.remove_from_project }
  runner.dependencies.select { |dependency| dependency.target == target }
        .each(&:remove_from_project)
  target.remove_from_project
end

project.main_group.children
       .select { |child| child.respond_to?(:name) && child.name == TARGET_NAME }
       .each(&:remove_from_project)

# Drop stale embed entries left behind by a previous run.
runner.copy_files_build_phases.each do |phase|
  phase.files.select { |file|
    file.display_name.to_s.include?(TARGET_NAME)
  }.each(&:remove_from_project)
end

# -------------------------------------------------------------- create target
widget = project.new_target(
  :app_extension,
  TARGET_NAME,
  :ios,
  DEPLOYMENT_TARGET
)

group = project.main_group.new_group(TARGET_NAME, TARGET_NAME)

widget_sources = [
  'LiveRideWidgetBundle.swift',
  'RideLiveActivity.swift',
  'RideActivityAttributes.swift'
]
widget_sources.each do |name|
  path = File.join(ios_dir, TARGET_NAME, name)
  unless File.exist?(path)
    abort "Missing #{path}; copy ios_native/ into ios/ before running this."
  end
  reference = group.new_reference(name)
  widget.add_file_references([reference])
end
group.new_reference('Info.plist')

# The attributes and the bridge also belong to the app target: the app creates
# the activity, the extension draws it, and both need the same type.
runner_group = project.main_group['Runner'] || project.main_group
[
  ['RideActivityAttributes.swift', File.join(ios_dir, 'Runner', 'RideActivityAttributes.swift')],
  ['LiveRideActivityBridge.swift', File.join(ios_dir, 'Runner', 'LiveRideActivityBridge.swift')],
  ['LiveRideActivityUpdater.swift', File.join(ios_dir, 'Runner', 'LiveRideActivityUpdater.swift')]
].each do |name, path|
  abort "Missing #{path}" unless File.exist?(path)
  already = runner.source_build_phase.files.any? do |file|
    file.file_ref && file.file_ref.display_name == name
  end
  next if already

  reference = runner_group.files.find { |file| file.display_name == name } ||
              runner_group.new_reference(name)
  runner.add_file_references([reference])
end

# ------------------------------------------------------------ build settings
team = runner.build_configurations
              .map { |config| config.build_settings['DEVELOPMENT_TEAM'] }
              .compact.first

widget.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{app_bundle_id}.#{TARGET_NAME}"
  settings['PRODUCT_NAME'] = TARGET_NAME
  settings['INFOPLIST_FILE'] = "#{TARGET_NAME}/Info.plist"
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['SKIP_INSTALL'] = 'YES'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['MARKETING_VERSION'] = '1.0'
  settings['CURRENT_PROJECT_VERSION'] = '1'
  settings['CLANG_ENABLE_MODULES'] = 'YES'
  settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = ''
  settings['DEVELOPMENT_TEAM'] = team if team && !team.empty?
end

# --------------------------------------------------------------- embed + link
runner.add_dependency(widget)

embed = runner.copy_files_build_phases.find do |phase|
  phase.symbol_dst_subfolder_spec == :plug_ins
end
embed ||= runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.dst_path = ''
embed.run_only_for_deployment_postprocessing = '0'
build_file = embed.add_file_reference(widget.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

# ----------------------------------------------------- break the build cycle
#
# Flutter's generated "Thin Binary" run-script phase reads the whole built
# .app, and the embed phase writes an .appex into that same .app. Left in the
# order Xcode creates them (embed last), Xcode 15+ refuses the build with
# "Cycle inside Runner; building could produce unreliable results", naming the
# Thin Binary script and the Embed Foundation Extensions copy phase.
#
# The fix is purely an ordering one: the extension has to be embedded BEFORE
# the binary is thinned, so the script sees a finished bundle. Doing it here
# means nobody has to drag phases around in Xcode after regenerating the
# shell, which is exactly the manual step this project refuses to require.
def flutter_script_phase?(phase)
  return false unless phase.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase)

  name = phase.name.to_s
  script = phase.shell_script.to_s
  name.include?('Thin Binary') ||
    script.include?('embed_and_thin') ||
    script.include?('xcode_backend.sh\" thin') ||
    script.include?("xcode_backend.sh' thin")
end

embed_phase = runner.copy_files_build_phases.find do |phase|
  phase.symbol_dst_subfolder_spec == :plug_ins
end

phases = runner.build_phases.to_a
thin_index = phases.index { |phase| flutter_script_phase?(phase) }
embed_index = embed_phase && phases.index(embed_phase)

if thin_index && embed_index && embed_index > thin_index
  phases.delete_at(embed_index)
  phases.insert(thin_index, embed_phase)
  runner.build_phases.clear
  phases.each { |phase| runner.build_phases << phase }
  puts 'Moved "Embed Foundation Extensions" before "Thin Binary" ' \
       '(breaks the Xcode dependency cycle).'
elsif thin_index.nil?
  warn 'No Flutter "Thin Binary" phase found — check the phase order by hand ' \
       'if Xcode reports a dependency cycle.'
end

project.save

unless order_only
  puts "Added #{TARGET_NAME} (#{app_bundle_id}.#{TARGET_NAME}), " \
       "iOS #{DEPLOYMENT_TARGET}+."
end
puts 'Build phase order on Runner:'
runner.build_phases.each_with_index do |phase, index|
  label = phase.respond_to?(:name) && phase.name ? phase.name : phase.isa
  puts format('  %<index>d. %<label>s', index: index + 1, label: label)
end
puts 'Open Runner.xcworkspace and pick your team for both targets if Xcode asks.'
