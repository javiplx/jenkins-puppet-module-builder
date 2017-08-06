require 'jenkins/utils'

require 'stringio'
require 'fileutils'
require 'pathname'

module PuppetModuleHelper
  include Jenkins::Utils

  java_import Java.hudson.model.Result
  #java_import Java.Hudson.Maven.MavenModuleSet

  def perform(build, launcher, listener)

    env_vars = build.native.environment listener
    puppetdir = topdir(build) + puppetsrc

    # Run tests
    rspecdir = puppetdir + 'spec'
    if rspecdir.directory?

    if build.native.project.is_a?(Java::HudsonMaven::MavenModuleSet)
      testfile = topdir(build) + 'test-reports/TEST-puppet.xml'
    else
      testfile = 'TEST-puppet.xml'
    end

      rspec = StringIO.new
      rc = launcher.execute({'PATH'=>"/opt/rh/ruby193/root/usr/bin:#{env_vars['PATH']}", 'LD_LIBRARY_PATH'=>'/opt/rh/ruby193/root/usr/lib64', 'CI_SPEC_OPTIONS'=>"--format RspecJunitFormatter --out #{testfile}"}, '/opt/rh/ruby193/root/usr/bin/rake', {:out => rspec, :chdir => puppetdir} )
      launcher.execute({'PATH'=>"/opt/rh/ruby193/root/usr/bin:#{env_vars['PATH']}", 'LD_LIBRARY_PATH'=>'/opt/rh/ruby193/root/usr/lib64'}, '/opt/rh/ruby193/root/usr/bin/rake', 'spec_clean', {:chdir => puppetdir} )

      if rc != 0
        listener.error "RSpec failures: #{rc}"
        rspec.string.lines.each{ |line| listener.warn line.chop }
        build.native.result = Result.fromString 'FAILURE' if fail_on_rspec? || build.native.project.is_a?(Java::HudsonMaven::MavenModuleSet)
        return if fail_on_rspec?
      end

      # If we delay cleaning, sonar will fail later ???
      #launcher.execute('rm', '-rf', 'Rakefile', 'spec', '=', {:chdir => puppetdir} )
      launcher.execute('rm', '-rf', 'Rakefile', 'spec', '=', {:chdir => puppetdir} )

    end

    return if skip_build?(puppetdir, launcher, listener, env_vars)

    # Build module
    build_info = StringIO.new
    rc = launcher.execute('puppet', 'module' , 'build', {:out => build_info, :chdir => puppetdir} )
    if rc != 0
      listener.error "Cannot build puppet module\n#{build_info.string}"
      build.native.result = Result.fromString 'FAILURE'
      launcher.execute('rm', '-rf', 'pkg', {:chdir => puppetdir} )
      return
    end

    build_line = build_info.string.lines.tap{ |l| listener.warn "build: #{l}" }.find{ |l| l.start_with? 'Module built: ' }.split

    module_file = Pathname.new build_line.last
    workspace = Pathname.new env_vars['WORKSPACE']

    artifact_list = java.util.HashMap.new( module_file.basename.to_s => module_file.relative_path_from(workspace).to_s )

    artifact_manager = build.native.artifact_manager
    artifact_manager.archive(topdir(build).native, launcher.native, listener.native, artifact_list)

    listener.info "Built puppet module #{module_file}"

  end

  private

  def skip_build?(moduledir, launcher, listener, env_vars)
    false
  end

  def fail_on_rspec?
    true
  end

end

class PuppetModuleBuilder < Jenkins::Tasks::Builder
  include PuppetModuleHelper

  display_name 'Build puppet module from a subdirectory'

  attr_reader :puppetsrc

  def initialize(opts)
    @puppetsrc = opts['puppetsrc']
  end

  class DescriptorImpl < Jenkins::Model::DefaultDescriptor
    attr_accessor :puppetsrc
  end

  describe_as Java.hudson.tasks.Builder, :with => DescriptorImpl

  private

  # Skip if metadata.json didn't change since last build
  def skip_build?(moduledir, launcher, listener, env_vars)
    if first = env_vars['GIT_PREVIOUS_COMMIT']
      last = env_vars['GIT_COMMIT']
      commit_list = StringIO.new
      # Check only Module file or also "#{puppetsrc}/manifests", "#{puppetsrc}/templates" and maybe other directories ???
      # Which one use for directory ???
      launcher.execute('git', 'log', '--oneline' ,"#{first}..#{last}", '--', "metadata.json", {:out => commit_list, :chdir => moduledir} )
      if commit_list.string.lines.to_a.empty?
        listener.info "No new commits 0 under '#{puppetsrc}', skip module build"
        return true
      end
    end
  end

  def fail_on_rspec?
    false
  end

end

class PuppetBuilder < Jenkins::Tasks::Builder
  include PuppetModuleHelper

  display_name 'Build standalone puppet module'

  java_import Java.hudson.model.Result

  private

  # Skip if no changes on metadata.json, also sets the module bugfix version
  def skip_build?(moduledir, launcher, listener, env_vars)

    lastchange = StringIO.new
    launcher.execute('git', 'log', '-1', '--format=%H' , '--', 'metadata.json', {:out => lastchange, :chdir => moduledir} )
    if lastchange.string.tap{ |s| listener.info " * 1 * #{s}" }.lines.to_a.empty?
      listener.info 'No new commits 1 , skip module build'
      return true
    end

    commit_list = StringIO.new
    launcher.execute('git', 'log', '--first-parent', '--oneline' ,"#{lastchange.string.chomp}..", {:out => commit_list, :chdir => moduledir} )
    if commit_list.string.tap{ |s| listener.info " * 2 * #{s}" }.lines.to_a.empty?
      listener.fatal 'No new commits 2 , skip module build'
      build.native.result = Result.fromString 'FAILURE'
      return true
    end

    # Update module version
    modulefile = topdir(build) + 'metadata.json'
    count = commit_list.string.lines.to_a.size
    # BUGFIX: metadata is a json, so this code is not valid anymore
    #metadata = modulefile.read
    #modulefile.native.write metadata.lines.collect{ |l| l.start_with?('version') ? l.sub(/'$/,".#{count}'") : l }.join('\n') , 'UTF-8'
  end

end

class PuppetModulePublisher < Jenkins::Tasks::Publisher
  include Jenkins::Utils

  java_import Java.hudson.model.Result
  java_import Java.hudson.model.Cause
  java_import Java.hudson.model.ParametersAction
  java_import Java.hudson.model.StringParameterValue

  display_name 'Publish puppet module'

  def perform(build, launcher, listener)

    listener.warn('No puppet module to publish') if build.native.artifacts.empty?

    # Once we set some RC tag on module version for branches, we can probably skip this test
    remote_head = StringIO.new
    launcher.execute('git', 'ls-remote', 'origin' ,'HEAD', {:out => remote_head, :chdir => topdir(build)} )
    if remote_head.string.chomp.split.first != build.native.environment(listener)['GIT_COMMIT']
      listener.warn 'Skip puppet module publication, not in remote HEAD'
      return
    end

    deployed = []
    build.native.artifacts.each do |artifact|
      if artifact.file_name.start_with?('n4t-') &&
            artifact.file_name.end_with?('.tar.gz')
        listener.info "Publishing puppet module #{artifact.file.name}"
        FileUtils.cp artifact.file.canonical_path, '/var/lib/puppet-library'
        deployed << artifact.file_name
      end
    end

    return if deployed.empty?

  end

  private

  def get_actions(filename)
    # The optional '7' is there for tomcat7 module, and the 4 for log4j, and the 1 for the apis ...
    moduleparts = /([4a-z-]+[17]?)-([0-9]+\.[0-9]+\.[0-9]+(-[.0-9a-z-]+)?).tar.gz/.match filename
    modulename = StringParameterValue.new( 'MODULENAME' , moduleparts[1] )
    moduleversion = StringParameterValue.new( 'MODULEVERSION' , moduleparts[2] )
    return ParametersAction.new( [ modulename , moduleversion ] )
  end

end
