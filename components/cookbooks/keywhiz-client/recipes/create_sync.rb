require 'net/https'
require 'json'

directory '/opt/oneops/keywhiz/keysync/CA' do
        action :create
        recursive true
end

directory '/opt/oneops/keywhiz/keysync/clients' do
        action :create
        recursive true
end

#directory '#{node.workorder.rfcCi.ciAttributes.secretsmount}' do
#        action :create
#        recursive true
#end

#download kw-synch tool and start it with the config file
remote_file '/opt/oneops/keywhiz/keysync/keysync.tar.gz' do
  source node.keywhiz_sync_download_url
  mode '0755'
  action :create
end

#stop the keysync service so that the untar can overwrite the keysync binary
service "keysync" do
  supports :status => true, :restart => true
  action [:stop]
  only_if { File.exists?("/opt/oneops/keywhiz/keysync/keysync") }
end

execute 'extract_tar' do
  command 'tar --overwrite -xvzf keysync.tar.gz'
  cwd '/opt/oneops/keywhiz/keysync'
  only_if { File.exists?("/opt/oneops/keywhiz/keysync/keysync.tar.gz") }
end

file '/opt/oneops/keywhiz/keysync/clients/client.crt' do
  content node[:cert_content]
end

file '/opt/oneops/keywhiz/keysync/clients/key.encrypted' do
  content node[:key_content]
end

file '/opt/oneops/keywhiz/keysync/CA/cacert.crt' do
  content node[:ca_content]
end

execute "openssl rsa -in /opt/oneops/keywhiz/keysync/clients/key.encrypted -out /opt/oneops/keywhiz/keysync/clients/client.key -passin pass:#{node.sync_cert_passphrase}"

template "/opt/oneops/keywhiz/keysync/config.yaml" do
  source "keysync-config.erb"
  variables({
  	:user => node.workorder.rfcCi.ciAttributes.user,
	:group => node.workorder.rfcCi.ciAttributes.group,
	:secrets_dir => node.workorder.rfcCi.ciAttributes.secretsmount,
	:server => node.keywhiz_service_host + ":" + node.keywhiz_service_port
  })
end

template "/opt/oneops/keywhiz/keysync/clients/client.yaml" do
  source "keysync-client.erb"
  variables({
        :user => node.workorder.rfcCi.ciAttributes.user,
        :group => node.workorder.rfcCi.ciAttributes.group,
	:common_name => node.common_name 
  })
end

template "/usr/lib/systemd/system/keysync.service" do
  source "keysync-service.erb"
  owner "root"
  group "root"
  mode 00644
end

file "/etc/rsyslog.d/oneops-keysync.conf" do
	content ':syslogtag, isequal, "oneops-keysync:" /opt/oneops/log/keysync.log'
end

cookbook_file "/etc/logrotate.d/oneops-keysync" do
	source "keysync_logrotate"
	action :create
end

execute "systemctl daemon-reload"

service "keysync" do
  supports :status => true, :restart => true
  action [:enable, :reload, :restart]
end

service "rsyslog" do
  supports :status => true, :restart => true
  action [:enable, :restart]
end

#now check if keysync connected properly

ruby_block 'check_process' do
  block do
    sleep 3
    uri = URI('http://127.0.0.1:31738/metrics')
    metrics_string = Net::HTTP.get(uri) #string
    metrics = JSON.parse(metrics_string)
    metrics.each do |metric| 
    	if (metric["metric"] == 'keysync.seconds_since_last_success')
    	    metric_value = metric["value"]
    	    Chef::Log.info("Last connected successfully " + metric_value.to_s + " sencods ago")
    	    if (metric_value > 0 && metric_value < 5)	
    		Chef::Log.info("keysync working fine.")
    		break
    	    else
    		Chef::Log.error("keysync not connected.")
    		exit 1
    	    end
    	end
    end
  end
  action :run
end

