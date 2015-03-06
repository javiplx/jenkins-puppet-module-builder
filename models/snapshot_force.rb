require 'stringio'
require 'rexml/document'

class SnapshotForce < Jenkins::Tasks::BuildWrapper

  display_name "(FON) force snapshot on pom"

  def setup(build, launcher, listener)

    return unless build.native.project.is_a?(Java::HudsonMaven::MavenModuleSet)

    outstr = StringIO.new
    launcher.execute('git', 'describe', {:out => outstr, :chdir => build.workspace} )
    return if outstr.string.chomp.split('-').length == 1

    pom = build.workspace.native.child 'pom.xml'
    doc = REXML::Document.new pom.read_to_string
    listener.info "Adding 'SNAPSHOT' to version declared in pom"
    version = doc.root.elements['version'].text.split('.').collect{ |v| v.to_i }
    version[2] += 1
    doc.root.elements['version'].text = "#{version.join('.')}-SNAPSHOT"
    pom.write(doc.to_s, 'UTF-8')

  end

end
