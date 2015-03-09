require 'jenkins/utils'

require 'fileutils'

class DpkgBuilder < Jenkins::Tasks::Builder
  include Jenkins::Utils

  java_import Java.hudson.model.Result

  display_name "(FON) Build debian package"

  def perform(build, launcher, listener)

    debiandir = topdir(build)
    if debiandir == build.workspace
      listener.warn "Cannot build debian packages on workspace root"
      return
    end

    build_info = StringIO.new
    rc = launcher.execute('dpkg-buildpackage', '-uc', '-b', '-rfakeroot', {:out => build_info, :chdir => debiandir} )
    if rc != 0
      listener.error "Cannot build debian package\n#{build_info.string}"
      build.native.result = Result.fromString 'FAILURE'
    end

    build_line = build_info.string.lines.find{ |l| l.start_with? 'dpkg-deb: building package ' }.chomp.split

    dpkg = /`\.\.\/(.*\.deb)'\./.match(build_line.last)[1]
    listener.info "SUCCEED : package is \n#{dpkg}"

    artifact_list = { dpkg => "gitclone/#{dpkg}" }

    artifact_manager = build.native.artifact_manager
    artifact_manager.archive(debiandir.parent.native, launcher.native, listener.native, artifact_list)

    listener.info "Built puppet module #{module_file}"

  end

end

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

    jenkins_project.artifacts.each do |artifact|
      if artifact.file_name.end_with?('.deb')
        return artifact.getFile
      end
    end
    return unless jenkins_project.kind_of?(MavenModuleSetBuild)

    artifacts = jenkins_project.maven_artifacts
    return if artifacts.nil?

    record = artifacts.module_records.first
    dpkg = record.attachedArtifacts.first
    return if dpkg.nil?

    dpkg.getFile(jenkins_project.getModuleLastBuilds.values.first)
  end

end
