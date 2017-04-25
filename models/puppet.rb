require 'jenkins/utils'

require 'fileutils'
require 'pathname'

class PuppetModuleBuilder < Jenkins::Tasks::Builder
  include Jenkins::Utils

  java_import Java.hudson.model.Result
  java_import Java.hudson.plugins.git.extensions.impl.RelativeTargetDirectory

  display_name "Build puppet module"

  attr_reader :puppetsrc

  def initialize(opts)
    @puppetsrc = opts['puppetsrc']
  end

  def perform(build, launcher, listener)

    env_vars = build.native.environment listener
    puppetdir = topdir(build) + puppetsrc

    # Run tests
    #unless build.native.project.is_a? Java::HudsonMaven::MavenModuleSet
      rspec = StringIO.new
      rc = launcher.execute('rake', 'test', {:out => rspec, :chdir => puppetdir} )
      if rc != 0
        listener.error "RSpec failures:"
        rspec.string.lines.each{ |line| listener.error line }
        build.native.result = Result.fromString 'FAILURE'
        return
      end
    #end

    # Tree cleanup
    launcher.execute('rake', 'spec_clean', {:chdir => puppetdir} )
    launcher.execute('rm', '-rf', 'pkg', '"="', 'Rakefile', 'spec', {:chdir => puppetdir} )

    if first = env_vars['GIT_PREVIOUS_SUCCESSFUL_COMMIT'] || env_vars['GIT_PREVIOUS_COMMIT']
      last = env_vars['GIT_COMMIT']
      commit_list = StringIO.new
      launcher.execute('git', 'log', '--oneline' ,"#{first}..#{last}", '--', "#{puppetsrc}/Modulefile", "#{puppetsrc}/manifests", "#{puppetsrc}/templates", {:out => commit_list, :chdir => topdir(build)} )
      if commit_list.string.lines.to_a.empty?
        listener.warn "No new commits under '#{puppetsrc}', skip module build"
        return
      end
    end

    # Build module
    build_info = StringIO.new
    rc = launcher.execute('puppet', 'module' , 'build', {:out => build_info, :chdir => puppetdir} )
    if rc != 0
      listener.error "Cannot build puppet module\n#{build_info.string}"
      build.native.result = Result.fromString 'FAILURE'
      return
    end

    build_line = build_info.string.lines.find{ |l| l.start_with? 'Module built: ' }.chomp.split

    module_file = Pathname.new build_line.last
    workspace = Pathname.new env_vars['WORKSPACE']

    artifact_list = java.util.HashMap.new( module_file.basename.to_s => module_file.relative_path_from(workspace).to_s )

    artifact_manager = build.native.artifact_manager
    artifact_manager.archive(topdir(build).native, launcher.native, listener.native, artifact_list)

    listener.info "Built puppet module #{module_file}"

  end

  class DescriptorImpl < Jenkins::Model::DefaultDescriptor
    attr_accessor :puppetsrc
  end

  describe_as Java.hudson.tasks.Builder, :with => DescriptorImpl

end

class PuppetModulePublisher < Jenkins::Tasks::Publisher
  include Jenkins::Utils

  java_import Java.hudson.model.Result
  java_import Java.hudson.model.Cause
  java_import Java.hudson.model.ParametersAction
  java_import Java.hudson.model.StringParameterValue

  display_name "(FON) Publish puppet module"

  def perform(build, launcher, listener)

    listener.warn("No puppet module to publish") if build.native.artifacts.empty?

    if build.native.result.worse_than? Result.fromString('SUCCESS')
      listener.warn "Skip puppet module publication for non-stable build"
      return
    end

    # Once we set some RC tag on module version for branches, we can probably skip this test
    remote_head = StringIO.new
    launcher.execute('git', 'ls-remote', 'origin' ,'HEAD', {:out => remote_head, :chdir => topdir(build)} )
    if remote_head.string.chomp.split.first != build.native.environment(listener)['GIT_COMMIT']
      listener.warn "Skip puppet module publication, not in remote HEAD"
      return
    end

    deployed = []
    build.native.artifacts.each do |artifact|
      if artifact.file_name.start_with?('fon-') &&
            artifact.file_name.end_with?('.tar.gz')
        listener.info "Publishing puppet module #{artifact.file.name}"
        FileUtils.cp artifact.file.canonical_path, '/var/lib/puppet-library'
        deployed << artifact.file_name
      end
    end

    return if deployed.empty?

    cause = Cause::UpstreamCause.new(build.native)
    deploy_project = Java.jenkins.model.Jenkins.instance.getItem('deploy-puppet')

    deployed.each do |filename|
      deploy_project.scheduleBuild( deploy_project.getQuietPeriod() , cause , get_actions(filename) )
    end

  end

  private

  def get_actions(filename)
    # The optional '7' is there for tomcat7 module
    moduleparts = /([a-z-]+7?)-([.0-9a-z-]+).tar.gz/.match filename
    modulename = StringParameterValue.new( 'MODULENAME' , moduleparts[1] )
    moduleversion = StringParameterValue.new( 'MODULEVERSION' , moduleparts[2] )
    return ParametersAction.new( [ modulename , moduleversion ] )
  end

end
