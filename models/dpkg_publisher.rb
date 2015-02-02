require 'fileutils'

class DpkgPublisher < Jenkins::Tasks::Publisher

  java_import Java.hudson.model.Result

  display_name '(FON) Publish maven dpkg artifacts'

  def perform(build, launcher, listener)
    artifacts = build.native.maven_artifacts
    return if artifacts.nil?
    record = artifacts.module_records.first
    dpkg = record.attachedArtifacts.first
    file = dpkg.getFile(build.native.getModuleLastBuilds.values.first)
    FileUtils.cp file.canonical_path , "/tmp"
    unless system( "update_repo.py --force /tmp/#{file.name}" )
      listener.error "Cannot publish #{file.name}"
      build.native.result = Result.fromString 'FAILURE'
    end
  end

end
