require 'fileutils'
require 'pathname'

class PuppetModuleBuilder < Jenkins::Tasks::Builder

  java_import Java.hudson.model.Result

  display_name "(FON) Build puppet module"

  def perform(build, launcher, listener)

    env_vars = build.native.environment listener
    puppetdir = build.workspace + 'src' + 'puppet'

    if first = env_vars['GIT_PREVIOUS_SUCCESSFUL_COMMIT'] || env_vars['GIT_PREVIOUS_COMMIT']
      last = env_vars['GIT_COMMIT']
      commit_list = StringIO.new
      launcher.execute('git', 'log', '--oneline' ,"#{first}..${last}", '--', 'src/puppet', {:out => commit_list} )
      if commit_list.string.lines.empty
        listener "No new commits under 'src/puppet', skip module build"
        return
      end
    end

    # Tree cleanup
    launcher.execute('rm', '-rf', 'pkg', '"="', 'Rakefile', 'spec', {:chdir => puppetdir} )

    # Run tests
    rc = launcher.execute('rake', 'test', {:chdir => puppetdir} )
    if rc != 0
      listener.warning "Errors on rspec examples"
      build.native.result = Result.fromString 'UNSTABLE'
    end

    # Build module
    build_info = StringIO.new
    launcher.execute('rake', 'spec_clean', {:chdir => puppetdir} )
    rc = launcher.execute('puppet', 'module' , 'build', {:out => build_info, :chdir => puppetdir} )
    if rc != 0
      build_line = build_info.string.lines.find{ |l| l.start_with? 'Module built: ' }.chomp.split

      module_file = Pathname.new build_line.last
      workspace = Pathname.new env_vars['WORKSPACE']

      artifact_list = { module_file.basename.to_s => module_file.relative_path_from(workspace).to_s }

      artifact_manager = build.native.artifact_manager
      artifact_manager.archive(build.workspace.native, launcher.native, listener.native, artifact_list)

      listener.info "Built puppet module #{module_file}"
    else
      listener.error "Cannot build puppet module"
      build.native.result = Result.fromString 'FAILURE'
    end

  end

end

class PuppetModulePublisher < Jenkins::Tasks::Publisher

  java_import Java.hudson.model.Result

  display_name "(FON) Publish puppet module"

  def perform(build, launcher, listener)
    build.native.artifacts.each do |artifact|
      if artifact.file_name.start_with?('fon-') &&
            artifact.file_name.end_with?('.tar.gz')
        FileUtils.cp artifact.file.canonical_path, '/var/lib/puppet-library'
      end
    end
  end

end
