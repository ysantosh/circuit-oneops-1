#
# Cookbook Name:: solrcloud
# Recipe:: solrcloud.rb
#
# The recipie extracts the solr.war and copies the WEB-INF/lib/ jars to solr-war-lib folder.
#
#

extend Java::Util

# Wire java util to chef resources.
Chef::Resource::RubyBlock.send(:include, Java::Util)

ci = node.workorder.rfcCi.ciAttributes;
solr_version = ci[:solr_version]
solr_format = ci[:solr_format]
solr_package_type = ci[:solr_package_type]
solr_file_name = "#{solr_package_type}-"+"#{solr_version}."+"#{solr_format}"
solr_file_woext = "#{solr_package_type}-"+"#{solr_version}"
solr_filepath = "#{node['user']['dir']}/#{solr_file_name}"
config_name = ci[:config_name]
zk_host_fqdns = ''

solr_extract_path = "#{node['user']['dir']}/tmp/tgz"
solr_war_lib = "#{node['user']['dir']}/solr-war-lib"
solr_config = "#{node['user']['dir']}/solr-config"
solr_cores = "#{node['user']['dir']}/solr-cores"
solr_default_dir = "#{solr_config}/default"

solr_base_url = ci['solr_url']
solr_url = "#{solr_base_url}/#{solr_package_type}/#{solr_version}/#{solr_file_name}"



Chef::Log.info("Download solr from gec-nexus: #{solr_url}")
remote_file solr_filepath do
  source "#{solr_url}"
  owner "#{node['solr']['user']}"
  group "#{node['solr']['user']}"
  mode '0644'
  action :create_if_missing
end

Chef::Log.info('Create Directory "solr-war-lib" ')
directory "#{solr_war_lib}" do
  owner "#{node['solr']['user']}"
  group "#{node['solr']['user']}"
  mode '0755'
  action :create
end

Chef::Log.info('Create Directory "solr-config" ')
directory "#{solr_config}" do
  owner "#{node['solr']['user']}"
  group "#{node['solr']['user']}"
  mode '0755'
  action :create
end

Chef::Log.info('Create Directory "solr-config/default" ')
directory "#{solr_default_dir}" do
  owner "#{node['solr']['user']}"
  group "#{node['solr']['user']}"
  mode '0755'
  action :create
end

Chef::Log.info('Create Directory "solr-cores" ')
directory "#{solr_cores}" do
  not_if { ::File.directory?("#{node['user']['dir']}/solr-cores") }
  owner "#{node['solr']['user']}"
  group "#{node['solr']['user']}"
  mode '0755'
  action :create
end

Chef::Log.info('Create Directory "tmp" ')
directory "#{node['user']['dir']}/tmp" do
  owner "#{node['solr']['user']}"
  group "#{node['solr']['user']}"
  mode '0755'
  action :create
end

Chef::Log.info('Create Directory "solr_extract_path" ')
directory "#{solr_extract_path}" do
  owner "#{node['solr']['user']}"
  group "#{node['solr']['user']}"
  mode '0755'
  action :create
end

Chef::Log.info('UnPack solr.war and extract the WEB-INF/lib to solr-war-lib/ folder')
bash 'unpack_solr_war' do
  user "#{node['solr']['user']}"
  code <<-EOH
    cd #{node['user']['dir']}
    rm -rf solr-*.txt
    echo #{solr_version} > solr-#{solr_version}.txt
    mkdir /app/tmp/tgz
    mv #{solr_file_name} #{node['user']['dir']}/tmp/tgz/
    cd #{node['user']['dir']}/tmp/tgz
    tar -xvf #{solr_file_name}
    cp #{solr_file_woext}/dist/#{solr_file_woext}.war ../
    cd ..
    jar xvf #{solr_file_woext}.war
    rm -rf #{node['user']['dir']}/solr-war-lib/*
    rm -rf #{node['user']['dir']}/solr.war
    cp #{node['user']['dir']}/tmp/WEB-INF/lib/* #{solr_war_lib}
    cp #{solr_file_woext}.war solr.war
    cp solr.war #{node['user']['dir']}
    rm -rf #{node['user']['dir']}/solr-config/default/*   
  EOH
  not_if { ::File.exists?("#{node['user']['dir']}/solr-#{solr_version}.txt") }
end

bash 'unpack_conf_dir' do
  user "#{node['solr']['user']}"
  code <<-EOH
    cp -irf #{node['user']['dir']}/tmp/tgz/#{solr_file_woext}/example/example-DIH/solr/solr/conf/* #{node['user']['dir']}/solr-config/default/
  EOH
  only_if { ::File.exists?("#{node['user']['dir']}/tmp/tgz/#{solr_file_woext}/example/example-DIH/solr/solr/conf") }
end

bash 'upload_ext_jars' do
  user "#{node['solr']['user']}"
  code <<-EOH
    cp #{node['user']['dir']}/tmp/tgz/#{solr_file_woext}/example/lib/ext/*.jar #{solr_war_lib}
    cp #{node['user']['dir']}/tmp/tgz/#{solr_file_woext}/example/lib/ext/*.jar #{node['tomcat']['dir']}/lib
  EOH
  only_if { ::File.exists?("#{node['user']['dir']}/tmp/tgz/#{solr_file_woext}/example/lib") }
end

zk_select = ci[:zk_select]
if "#{zk_select}".include? "Internal"
  Chef::Log.info("Download zookeeper from gec-nexus: http://gec-maven-nexus.walmart.com/nexus/content/groups/public/org/apache/zookeeper/3.4.6/zookeeper-3.4.6.tar.gz")
  remote_file "#{node['zookeeper']['filename']}" do
    source "#{node['zookeeper']['url']}"
    owner "#{node['solr']['user']}"
    group "#{node['solr']['user']}"
    mode '0644'
    action :create_if_missing
  end

  ## Install zookeeper
  bash "install_zookeeper" do
    user "#{node['solr']['user']}"
    Chef::Log.info("Install zookeeper locally.")
    code <<-EOH
      cd #{node['user']['dir']}
      chown app:app zookeeper-3.4.6.tar.gz
      tar -xvf zookeeper-3.4.6.tar.gz
      chown app:app zookeeper-3.4.6/
      /app/zookeeper-3.4.6/bin/zkServer.sh stop       
      mv #{node['user']['dir']}/zookeeper-3.4.6/conf/zoo_sample.cfg #{node['user']['dir']}/zookeeper-3.4.6/conf/zoo.cfg
      /app/zookeeper-3.4.6/bin/zkServer.sh start
    EOH
  end
  zk_host_fqdns = "#{node['ipaddress']}:2181"
else
  zk_host_fqdns = ci[:zk_host_fqdns]
end
bash "update_zookeeper_string" do
  code <<-EOH
    grep -q -F 'zkHost' #{node['tomcat']['dir']}/bin/setenv.sh || echo 'export CATALINA_OPTS=\"\$CATALINA_OPTS -DzkHost=#{zk_host_fqdns}\"' >> #{node['tomcat']['dir']}/bin/setenv.sh
  EOH
end

downloadconfig("#{zk_host_fqdns}","#{config_name}")
uploaddefaultconfig("#{zk_host_fqdns}","#{config_name}")

Chef::Log.info('Create/Update the solr.xml in /solr-cores')
cookbook_file "#{node['user']['dir']}/solr-cores/solr.xml" do
  source "solr.xml"
  owner "#{node['solr']['user']}"
  group "#{node['solr']['user']}"
  mode '0755'
  action :create_if_missing
end

execute 'notify-tomcat-restart' do
  command "service tomcat#{node['tomcatversion']} restart"
  user "root"
  action :run
  only_if { ::File.exists?("/etc/init.d/tomcat#{node['tomcatversion']}") }
end


