Jenkins::Plugin::Specification.new do |plugin|
  plugin.name = "fon"
  plugin.display_name = "Fon Plugins"
  plugin.version = '0.2.0'
  plugin.description = 'Various jenkins items for building at Fon'

  plugin.developed_by "javier.palacios", "Javier Palacios <javier.palacios@fon.com>"

  plugin.depends_on 'ruby-runtime', '0.12'
end
