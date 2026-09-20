#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds the Live Ride watchOS companion to the generated Xcode project.
#
# The watch app exists for exactly one reason: live heart rate. Reading
# HealthKit from the iPhone returns samples the watch wrote earlier — tens of
# seconds late, minutes late with the screen off — which on a bike computer is
# not a heart rate. Only an `HKWorkoutSession` running ON THE WATCH keeps the
# wrist sensor sampling every second and allowed to transmit.
#
# `flutter create` produces a single-target iOS project, so the watch target
# has to be added afterwards. Doing it by hand is a dozen screens of Xcode
# clicking that would have to be repeated every time the shell is
# regenerated — which is exactly the kind of "works on my machine" step this
# project refuses to require.
#
# The script is idempotent: a second run replaces the target instead of
# adding a second one.
#
# Usage: ruby add_watch_target.rb <path-to-ios-dir> <app-bundle-id>

require 'xcodeproj'

ios_dir = ARGV[0] || 'ios'
app_bundle_id = ARGV[1] || 'pl.marekpiatak.liveride'

TARGET_NAME = 'LiveRideWatch'
DEPLOYMENT_TARGET = '9.0'

project_path = File.join(ios_dir, 'Runner.xcodeproj')
abort "No Xcode project at #{project_path}" unless Dir.exist?(project_path)

project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |target| target.name == 'Runner' }
abort 'No Runner target in the project' if runner.nil?

# ---------------------------------------------------------------- clean slate
project.targets.select { |target| target.name == TARGET_NAME }.each do |target|
  target.build_phases.each { |phase| phase.remove_from_project }
  runner.dependencies.select { |dependency| dependency.target == target }
        .each(&:remove_from_project)
  target.remove_from_project
end

project.main_group.children
       .select { |child| child.respond_to?(:name) && child.name == TARGET_NAME }
       .each(&:remove_from_project)

runner.copy_files_build_phases.each do |phase|
  phase.files.select { |file|
    file.display_name.to_s.include?(TARGET_NAME)
  }.each(&:remove_from_project)
end

# -------------------------------------------------------------- create target
#
# A single-target watch app (watchOS 7+), not the old app + extension pair:
# the two-target layout has been deprecated since Xcode 14 and doubles the
# signing work for no benefit here.
watch = project.new_target(:application, TARGET_NAME, :watchos, DEPLOYMENT_TARGET)

group = project.main_group.new_group(TARGET_NAME, TARGET_NAME)
%w[LiveRideWatchApp.swift WatchWorkoutSession.swift].each do |name|
  path = File.join(ios_dir, TARGET_NAME, name)
  unless File.exist?(path)
    abort "Missing #{path}; copy ios_native/Watch into ios/#{TARGET_NAME} first."
  end
  watch.add_file_references([group.new_reference(name)])
end
group.new_reference('Info.plist')
group.new_reference('LiveRideWatch.entitlements')

# The phone side of the bridge belongs to the app target.
runner_group = project.main_group['Runner'] || project.main_group
bridge = 'LiveRideWatchBridge.swift'
bridge_path = File.join(ios_dir, 'Runner', bridge)
abort "Missing #{bridge_path}" unless File.exist?(bridge_path)
unless runner.source_build_phase.files.any? { |file|
  file.file_ref && file.file_ref.display_name == bridge
}
  reference = runner_group.files.find { |file| file.display_name == bridge } ||
              runner_group.new_reference(bridge)
  runner.add_file_references([reference])
end

# ------------------------------------------------------------ build settings
team = runner.build_configurations
             .map { |config| config.build_settings['DEVELOPMENT_TEAM'] }
             .compact.first

watch.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{app_bundle_id}.watchkitapp"
  settings['PRODUCT_NAME'] = 'Live Ride'
  settings['INFOPLIST_FILE'] = "#{TARGET_NAME}/Info.plist"
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['CODE_SIGN_ENTITLEMENTS'] = "#{TARGET_NAME}/LiveRideWatch.entitlements"
  settings['SDKROOT'] = 'watchos'
  settings['WATCHOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  settings['TARGETED_DEVICE_FAMILY'] = '4'
  settings['SUPPORTED_PLATFORMS'] = 'watchos watchsimulator'
  settings['SWIFT_VERSION'] = '5.0'
  settings['SKIP_INSTALL'] = 'YES'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['MARKETING_VERSION'] = '1.0'
  settings['CURRENT_PROJECT_VERSION'] = '1'
  settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = ''
  settings['DEVELOPMENT_TEAM'] = team if team && !team.empty?
end

# --------------------------------------------------------------- embed + link
runner.add_dependency(watch)

embed = runner.copy_files_build_phases.find do |phase|
  phase.name == 'Embed Watch Content'
end
embed ||= runner.new_copy_files_build_phase('Embed Watch Content')
embed.symbol_dst_subfolder_spec = :products_directory
embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
embed.run_only_for_deployment_postprocessing = '0'
build_file = embed.add_file_reference(watch.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# ----------------------------------------------------- break the build cycle
#
# Same trap as the Live Activity extension: Flutter's "Thin Binary" script
# reads the finished .app, and this phase writes into it. Left after the
# script, Xcode 15+ refuses the build with "Cycle inside Runner".
def flutter_thin_phase?(phase)
  return false unless phase.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase)

  name = phase.name.to_s
  script = phase.shell_script.to_s
  name.include?('Thin Binary') ||
    script.include?('embed_and_thin') ||
    script.include?('xcode_backend.sh\" thin') ||
    script.include?("xcode_backend.sh' thin")
end

phases = runner.build_phases.to_a
thin_index = phases.index { |phase| flutter_thin_phase?(phase) }
embed_index = phases.index(embed)
if thin_index && embed_index && embed_index > thin_index
  phases.delete_at(embed_index)
  phases.insert(thin_index, embed)
  runner.build_phases.clear
  phases.each { |phase| runner.build_phases << phase }
  puts 'Moved "Embed Watch Content" before "Thin Binary".'
end

project.save

puts "Added #{TARGET_NAME} (#{app_bundle_id}.watchkitapp), watchOS #{DEPLOYMENT_TARGET}+."
puts 'Build phase order on Runner:'
runner.build_phases.each_with_index do |phase, index|
  label = phase.respond_to?(:name) && phase.name ? phase.name : phase.isa
  puts format('  %<index>d. %<label>s', index: index + 1, label: label)
end
