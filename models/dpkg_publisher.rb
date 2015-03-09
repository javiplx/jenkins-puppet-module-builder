require 'jenkins/utils'

require 'fileutils'

class DpkgPublisher < Jenkins::Tasks::Publisher
  include Jenkins::Utils

  java_import Java.hudson.model.Result

  display_name '(FON) Publish maven dpkg artifacts'

  def perform(build, launcher, listener)

    remote_head = StringIO.new
    launcher.execute('git', 'ls-remote', 'origin' ,'HEAD', {:out => remote_head, :chdir => topdir(build)} )
    if remote_head.string.split.first != build.native.environment(listener)['GIT_COMMIT']
      listener.warn "Skip publication, not in remote HEAD"
      return
    end

    file = dpkg_artifacts(build.native)
    return if file.nil?

    FileUtils.cp file.canonical_path , "/tmp"
    unless system( "update_repo.py --force /tmp/#{file.name}" )
      listener.error "Cannot publish #{file.name}"
      build.native.result = Result.fromString 'FAILURE'
    end

  end

  private

  def dpkg_artifacts(jenkins_project)
    artifacts = jenkins_project.maven_artifacts
    return if artifacts.nil?

    record = artifacts.module_records.first
    dpkg = record.attachedArtifacts.first
    return if dpkg.nil?

    file = dpkg.getFile(jenkins_project.getModuleLastBuilds.values.first)
  end

end
