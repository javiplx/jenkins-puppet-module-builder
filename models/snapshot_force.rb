require 'rexml/document'

class SnapshotForce < Jenkins::Tasks::BuildWrapper

  display_name "(FON) force snapshot on pom"

  def setup(build, launcher, listener)
    pom = build.workspace.native.child 'pom.xml'
    doc = REXML::Document.new pom.read_to_string
    listener.info "Adding 'SNAPSHOT' to version declared in pom"
    doc.root.elements['version'].text += '-SNAPSHOT'
    pom.write(doc.to_s, 'UTF-8')
  end

end
