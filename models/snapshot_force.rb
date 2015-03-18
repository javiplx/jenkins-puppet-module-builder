require 'jenkins/utils'

require 'stringio'
require 'rexml/document'

class SnapshotForce < Jenkins::Tasks::BuildWrapper
  include Jenkins::Utils

  display_name "(FON) force snapshot package versions"

  def setup(build, launcher, listener)

    listener.info "Adding 'SNAPSHOT' to package version"

    if build.native.project.is_a? Java::HudsonMaven::MavenModuleSet
      return maven_snapshot(topdir(build)+'pom.xml', listener)
    end

    buildxml = topdir(build) + 'build.xml'
    if buildxml.exist?
      return ant_snapshot(buildxml, listener)
    end

  end

  private

  def ant_snapshot(buildxml, listener)
    launcher = buildxml.create_launcher listener

    outstr = StringIO.new
    launcher.execute('git', 'describe', {:out => outstr, :chdir => buildxml.parent} )
    return if outstr.string.chomp.split('-').length == 1

    doc = REXML::Document.new buildxml.read
    version = doc.root.elements.find{ |e| e.name == 'property' && e.attributes['name'] == 'version' }
    vers = version.attributes['value'].split('.').collect{ |v| v.to_i }
    vers[2] += 1
    version.attributes['value'] = "#{vers.join('.')}~#{Time.now.strftime('%Y%m%d%H%M%S')}"
    buildxml.write doc.to_s
  end

  def maven_snapshot(pom, listener)
    launcher = pom.create_launcher listener

    outstr = StringIO.new
    launcher.execute('git', 'describe', {:out => outstr, :chdir => pom.parent} )
    return if outstr.string.chomp.split('-').length == 1

    doc = REXML::Document.new pom.read
    version = doc.root.elements['version'].text.split('.').collect{ |v| v.to_i }
    version[2] += 1
    doc.root.elements['version'].text = "#{version.join('.')}-SNAPSHOT"
    pom.write doc.to_s
  end

end
