
env_name = node.workorder.payLoad["Environment"][0]["ciName"]
cloud_name = node.workorder.cloud.ciName

lb_service_type = node.lb.lb_service_type

exit_with_error "#{lb_service_type} service not found. either add it or change service type" if !node.workorder.services.has_key?("#{lb_service_type}")

cloud_service = nil
if !node.workorder.services["#{lb_service_type}"].nil? &&
    !node.workorder.services["#{lb_service_type}"][cloud_name].nil?

  cloud_service = node.workorder.services["#{lb_service_type}"][cloud_name]
end

exit_with_error "no cloud service defined or empty" if cloud_service.nil?

case cloud_service[:ciClassName].split(".").last.downcase
  
  when /octavia/
    include_recipe "lb::build_load_balancers"
    include_recipe "octavia::update"

  when /netscaler/
    include_recipe "lb::add"

  when /azure_lb/
    include_recipe "lb::add"
end
