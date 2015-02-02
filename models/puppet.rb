require 'pathname'

class PuppetModuleBuilder < Jenkins::Tasks::Builder

  display_name "(FON) Build puppet module"

  def perform(build, launcher, listener)

    puppetdir = build.workspace + 'src' + 'puppet'

    # Tree cleanup
    launcher.execute('rm', '-rf', 'pkg', '"="', 'Rakefile', 'spec', {:chdir => puppetdir} )

    # Run tests
    launcher.execute('rake', 'test', {:chdir => puppetdir} )

    # Build module
    build_info = StringIO.new
    launcher.execute('rake', 'spec_clean', {:chdir => puppetdir} )
    launcher.execute('puppet', 'module' , 'build', {:out => build_info, :chdir => puppetdir} )
    build_line = build_info.string.lines.find{ |l| l.start_with? 'Module built: ' }.chomp.split

    module_file = Pathname.new build_line.last
    workspace = Pathname.new build.native.environment(listener)['WORKSPACE']

    artifact_list = { module_file.basename.to_s => module_file.relative_path_from(workspace).to_s }

    artifact_manager = build.native.artifact_manager
    artifact_manager.archive(build.workspace.native, launcher.native, listener.native, artifact_list)

    listener.info "Built puppet module #{module_file}"

  end

end
