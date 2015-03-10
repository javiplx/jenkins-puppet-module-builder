require 'jenkins/utils'

require 'stringio'
require 'rexml/document'

class SnapshotForce < Jenkins::Tasks::BuildWrapper
  include Jenkins::Utils

  display_name "(FON) force snapshot package versions"

  def setup(build, launcher, listener)

    listener.info "Adding 'SNAPSHOT' to package version"

    if build.native.project.is_a? Java::HudsonMaven::MavenModuleSet
      return maven_snapshot(build, launcher)
    end

    buildxml = topdir(build) + 'build.xml'
    if buildxml.exist?
      return ant_snapshot(buildxml)
    end

  end

  private

  def ant_snapshot(buildxml)
    doc = REXML::Document.new buildxml.read
    version = doc.root.elements.find{ |e| e.name == 'property' && e.attributes['name'] == 'version' }
    vers = version.attributes['value'].split('.').collect{ |v| v.to_i }
    vers[2] += 1
    version.attributes['value'] = "#{vers.join('.')}~#{Time.now.strftime('%Y%m%d%H%M%S')}"
    buildxml.native.write(doc.to_s, 'UTF-8')
  end

  def maven_snapshot(build, launcher)

    outstr = StringIO.new
    launcher.execute('git', 'describe', {:out => outstr, :chdir => topdir(build)} )
    return if outstr.string.chomp.split('-').length == 1

    pom = topdir(build).native.child 'pom.xml'
    doc = REXML::Document.new pom.read_to_string
    version = doc.root.elements['version'].text.split('.').collect{ |v| v.to_i }
    version[2] += 1
    doc.root.elements['version'].text = "#{version.join('.')}-SNAPSHOT"
    pom.write(doc.to_s, 'UTF-8')

  end

end
