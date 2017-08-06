Jenkins::Plugin::Specification.new do |plugin|
  plugin.name = 'puppet-module-builder'
  plugin.display_name = 'Puppet module builder'
  plugin.version = '1.0.0'
  plugin.description = 'Build and publish puppet modules'

  plugin.developed_by 'javiplx', 'Javier Palacios <javiplx@gmail.com>'

  plugin.depends_on 'ruby-runtime', '0.12'
end
