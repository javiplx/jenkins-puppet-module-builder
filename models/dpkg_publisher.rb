require 'fileutils'

class DpkgPublisher < Jenkins::Tasks::Publisher

  display_name '(FON) Publish debian packages'

  def perform(build, launcher, listener)
    artifacts = build.native.maven_artifacts
    record = artifacts.module_records.first
    dpkg = record.attachedArtifacts.first
    file = dpkg.getFile(build.native.getModuleLastBuilds.values.first)
    FileUtils.cp file.canonical_path , "/tmp"
    system( "update_repo.py --force /tmp/#{file.name}" )
  end

end
