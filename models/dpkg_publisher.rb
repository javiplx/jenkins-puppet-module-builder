require 'jenkins/utils'

require 'fileutils'
require 'pathname'

class DpkgBuilder < Jenkins::Tasks::Builder
  include Jenkins::Utils

  java_import Java.hudson.model.Result

  display_name "(FON) Build debian package"

  attr_reader :srcdir

  def initialize(opts)
    @srcdir = opts['srcdir']
  end

  def perform(build, launcher, listener)

    debiandir = topdir(build) + srcdir
    if debiandir == build.workspace
      listener.fatal "Cannot build debian packages on workspace root"
      build.native.result = Result.fromString 'FAILURE'
      return
    end

    build_info = StringIO.new
    rc = launcher.execute('dpkg-buildpackage', '-uc', '-b', '-rfakeroot', {:out => build_info, :chdir => debiandir} )
    if rc != 0
      listener.error "Cannot build debian package\n#{build_info.string}"
      build.native.result = Result.fromString 'FAILURE'
    end

    build_line = build_info.string.lines.find{ |l| l.start_with? 'dpkg-deb: building package ' }.chomp.split

    # This will fail for sub-packages
    dpkgname = /`\.\.\/(.*\.deb)'\./.match(build_line.last)[1]

    dpkg = debiandir.parent + dpkgname
    workspace = Pathname.new build.workspace.realpath
    dpkgrealpath = Pathname.new(dpkg.realpath).relative_path_from(workspace)

    artifact_list = java.util.HashMap.new( dpkgname => dpkgrealpath.to_s )

    artifact_manager = build.native.artifact_manager
    artifact_manager.archive(debiandir.parent.native, launcher.native, listener.native, artifact_list)

    listener.info "Built debian package #{dpkgname}"

  end

  class DescriptorImpl < Jenkins::Model::DefaultDescriptor
    attr_accessor :srcdir
  end

  describe_as Java.hudson.tasks.Builder, :with => DescriptorImpl

end

class DpkgPublisher < Jenkins::Tasks::Publisher
  include Jenkins::Utils

  java_import Java.hudson.model.Result
  java_import Java.hudson.maven.MavenModuleSetBuild

  display_name '(FON) Publish dpkg artifacts'

  java_import Java.hudson.model.Cause
  java_import Java.hudson.maven.MavenModuleSetBuild

  def perform(build, launcher, listener)

    remote_head = StringIO.new
    launcher.execute('git', 'ls-remote', 'origin' ,'HEAD', {:out => remote_head, :chdir => topdir(build)} )
    if remote_head.string.split.first != build.native.environment(listener)['GIT_COMMIT']
      listener.warn "Skip publication, not in remote HEAD"
      return
    end

    files = dpkg_artifacts(build.native)
    return if files.empty?

    archiver_out = StringIO.new
    archiver = Jenkins::Launcher.new Java::Hudson::Launcher::LocalLauncher.new(listener.native)
    files.each do |file|
      FileUtils.cp file.canonical_path , "/tmp"
      unless archiver.execute('update_repo.py', '--force', "/tmp/#{file.name}", {:out => archiver_out} ).zero?
        listener.error "Cannot publish #{file.name}: #{archiver_out.string}"
        build.native.result = Result.fromString 'FAILURE'
      end
    end

    if build.native.result == Result.fromString('SUCCESS') && files.any?
        project = Java.jenkins.model.Jenkins.instance.getItem('run-functest')
        project.scheduleBuild( 10 + 2 * project.getQuietPeriod() , Cause::UpstreamCause.new(build.native) )
    end

  end

  private

  def dpkg_artifacts(jenkins_project)

    artifacts = jenkins_project.artifacts.select{ |artifact| artifact.file_name.end_with?('.deb') }.collect{ |artifact| artifact.getFile }
    return artifacts unless jenkins_project.kind_of?(MavenModuleSetBuild)

    last_build = jenkins_project.getModuleLastBuilds.values.first

    jenkins_project.maven_artifacts.module_records.each do |record|
      record.attachedArtifacts.each do |item|
        artifacts << item.getFile(last_build) if item.fileName.end_with?('.deb')
      end
    end

    artifacts
  end

end

class RepreproPublisher < Jenkins::Tasks::Publisher

  display_name "(FON) Publish resources on spices"

  java_import Java.org.jvnet.hudson.plugins.SSHBuildWrapper

  def perform(build, launcher, listener)

    env_vars = build.native.environment listener
    release = env_vars['PLATFORM_VERSION']

    files = dpkg_artifacts(build.native)
    return if files.empty?

    filelist = files.collect do |file|
      launcher.execute('scp', file.canonical_path, 'fondeb@spices.fon.ofi:/tmp')
      "/tmp/#{file.name}"
    end.join(' ')

    ssh_plugin = Java.jenkins.model.Jenkins.instance.descriptor(SSHBuildWrapper.java_class)
    ssh_site = ssh_plugin.sites.find{ |site| site.sitename == 'fondeb@spices.fon.ofi:22' }

    command = []
    command << ". /home/fondeb/.gpgea"
    command << "reprepro -b /opt/repositories/deb-resources includedeb #{release} #{filelist}"
    command << "rm -rf #{filelist}"

    ssh_site.executeCommand(listener.native.logger, command.join("\n"))

  end

  private

  def dpkg_artifacts(jenkins_project)

    artifacts = jenkins_project.artifacts.select{ |artifact| artifact.file_name.end_with?('.deb') }.collect{ |artifact| artifact.getFile }
    return artifacts unless jenkins_project.kind_of?(MavenModuleSetBuild)

    last_build = jenkins_project.getModuleLastBuilds.values.first

    jenkins_project.maven_artifacts.module_records.each do |record|
      record.attachedArtifacts.each do |item|
        artifacts << item.getFile(last_build) if item.fileName.end_with?('.deb')
      end
    end

    artifacts
  end

end
