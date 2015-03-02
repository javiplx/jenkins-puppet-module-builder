require 'fileutils'
require 'pathname'

class PuppetModuleBuilder < Jenkins::Tasks::Builder

  java_import Java.hudson.model.Result
  java_import Java.hudson.plugins.git.extensions.impl.RelativeTargetDirectory

  display_name "(FON) Build puppet module"

  attr_reader :puppetsrc

  def initialize(opts)
    @puppetsrc = opts['puppetsrc']
  end

  def perform(build, launcher, listener)

    env_vars = build.native.environment listener
    puppetdir = topdir(build) + puppetsrc

    # Run tests
    unless build.native.project.is_a? Java::HudsonMaven::MavenModuleSet
      rc = launcher.execute('rake', 'test', {:chdir => puppetdir} )
      if rc != 0
        listener.warning "Errors on rspec examples"
        build.native.result = Result.fromString 'UNSTABLE'
      end
    end

    if first = env_vars['GIT_PREVIOUS_SUCCESSFUL_COMMIT'] || env_vars['GIT_PREVIOUS_COMMIT']
      last = env_vars['GIT_COMMIT']
      commit_list = StringIO.new
      launcher.execute('git', 'log', '--oneline' ,"#{first}..#{last}", '--', 'src/puppet', {:out => commit_list, :chdir => build.workspace} )
      if commit_list.string.lines.to_a.empty?
        listener.warn "No new commits under 'src/puppet', skip module build"
        return
      end
    end

    # Tree cleanup
    launcher.execute('rake', 'spec_clean', {:chdir => puppetdir} )
    launcher.execute('rm', '-rf', 'pkg', '"="', 'Rakefile', 'spec', {:chdir => puppetdir} )

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

    artifact_list = { module_file.basename.to_s => module_file.relative_path_from(workspace).to_s }

    artifact_manager = build.native.artifact_manager
    artifact_manager.archive(build.workspace.native, launcher.native, listener.native, artifact_list)

    listener.info "Built puppet module #{module_file}"

  end

  class DescriptorImpl < Jenkins::Model::DefaultDescriptor
    attr_accessor :puppetsrc
  end

  describe_as Java.hudson.tasks.Builder, :with => DescriptorImpl

  def topdir( build )
    target = build.native.project.scm.extensions.get RelativeTargetDirectory.java_class
    if target && local_branch = target.relative_target_dir
      build.workspace + local_branch
    else
      build.workspace
    end
  end

end

class PuppetModulePublisher < Jenkins::Tasks::Publisher

  java_import Java.hudson.model.Result

  display_name "(FON) Publish puppet module"

  def perform(build, launcher, listener)

    listener.warn("No puppet module to publish") if build.native.artifacts.empty?

    if build.native.result.worse_than? Result.fromString('SUCCESS')
      listener.warn "Skip puppet module publication for non-stable build"
      return
    end

    remote_head = StringIO.new
    launcher.execute('git', 'ls-remote', 'origin' ,'HEAD', {:out => remote_head, :chdir => build.workspace} )
    if remote_head.string.chomp.split.first != build.native.environment(listener)['GIT_COMMIT']
      listener.warn "Skip puppet module publication, not in remote HEAD"
      return
    end

    build.native.artifacts.each do |artifact|
      if artifact.file_name.start_with?('fon-') &&
            artifact.file_name.end_with?('.tar.gz')
        listener.info "Publishing puppet module #{artifact.file.name}"
        FileUtils.cp artifact.file.canonical_path, '/var/lib/puppet-library'
      end
    end
  end

end
