class Moonshine::Manifest::Rails < Moonshine::Manifest
  include MySQLRecipes
  include PassengerRecipes
  include ApacheRecipes
  include RailsRecipes

  recipe :gems_from_environment
  recipe :directories
  recipe :mysql_server, :mysql_gem
  recipe :apache_server
  recipe :passenger_gem, :passenger_apache_module
  recipe :mysql_database
  recipe :passenger_site
  recipe :mysql_user, :bootstrap_database
  recipe :migrations

  def self.plugin(name)
    begin
      name = name.to_s.underscore
      Kernel.require File.join(working_directory, 'vendor', 'plugins', "moonshine_#{name}", 'lib', 'moonshine', "#{name}.rb")
      Module.include "moonshine/#{name}".camelize.constantize
    else
      true
    end
   end

  #database config
  configure(:database => YAML.load_file(File.join(working_directory, 'config', 'database.yml')))

  #capistrano
  cap = Capistrano::Configuration.new
  cap.load(:string => """
load 'deploy' if respond_to?(:namespace) # cap2 differentiator
Dir['#{working_directory}/vendor/plugins/*/recipes/*.rb'].each { |plugin| load(plugin) }
load '#{working_directory}/config/deploy.rb'
""")
  configure(:capistrano => cap)

  def gems_from_environment
    #rails configuration
    $rails_gem_installer = true
    begin
      require(File.join(self.class.working_directory, 'config', 'environment'))
    rescue Exception
      if defined?(RAILS_GEM_VERSION)
        #we can't parse the environment. as a last ditch effort, shell out and
        #try to install rails
        `gem install rails --version #{RAILS_GEM_VERSION}`
      end
      require(File.join(self.class.working_directory, 'config', 'environment'))
    end
    configure(:rails => ::Rails.configuration)

    configuration['rails'].gems.each do |gem_dependency|
      package(gem_dependency.name, {
        :provider => :gem,
        :source   => gem_dependency.source,
        :ensure  => gem_dependency.requirement ? gem_dependency.requirement.to_s : :latest
      })
    end
    package('rails', {
      :provider => :gem,
      :ensure  => (RAILS_GEM_VERSION rescue :latest)
    })
  end

  #Essentially replicates the deploy:setup command from capistrano. Includes
  #shared_children and app_symlinks arrays from capistrano.
  def directories
    deploy_to_array = configuration[:deploy_to].split('/').split('/')
    deploy_to_array.each_with_index do |dir, index|
      next if index == 0 || index >= (deploy_to_array.size-1)
      file '/'+deploy_to_array[1..index].join('/'), :ensure => :directory
    end
    dirs = [
      "#{configuration[:deploy_to]}",
      "#{configuration[:deploy_to]}/shared",
      "#{configuration[:deploy_to]}/releases"
    ]
    dirs += configuration[:capistrano].shared_children.map { |d| "#{configuration[:deploy_to]}/shared/#{d}" }
    if configuration[:capistrano].respond_to?(:app_symlinks)
      dirs += ["#{configuration[:deploy_to]}/shared/public"]
      dirs += configuration[:capistrano].app_symlinks.map { |d| "#{configuration[:deploy_to]}/shared/public/#{d}" }
    end
    dirs.each do |dir|
      file dir, :ensure => :directory, :owner => configuration[:user], :group => configuration[:user]
    end
  end
end