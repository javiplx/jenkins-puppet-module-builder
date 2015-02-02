require 'pathname'

class PuppetModuleBuilder < Jenkins::Tasks::Builder

  java_import Java.hudson.model.Result

  display_name "(FON) Build puppet module"

  def perform(build, launcher, listener)

    puppetdir = build.workspace + 'src' + 'puppet'

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
      workspace = Pathname.new build.native.environment(listener)['WORKSPACE']

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
