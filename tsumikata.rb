#!/usr/bin/env ruby

require 'jimuguri'
require 'aws-sdk-ecs'
require 'aws-sdk-applicationautoscaling'
require 'terminal-table'
require 'highline/import'

VERSION = '0.0.1'

class String
  def to_resource_name
    self.split('/').last
  end
end

class Array
  def cap_value(service)
    self.map { |c| c[:MinCap] if c[:Name] == service }.compact.last
  end
end

class Tsumikata
  def run
    app = Cli.new(name: 'tsumikata', description: 'Management ECS Scheduled Tasks.', version: VERSION)
    app.add_action 'version', 'print version' do
      version
    end

    app.add_action 'list', 'Print number of tasks in service.' do
      no_cluster_param if app.options[:cluster].nil?
      output(describe_services_per_cluster(app.options[:cluster]), app.options[:json])
    end

    app.add_action 'change', 'Change desired number of tasks in service.' do
      no_cluster_param if app.options[:cluster].nil?
      no_count_param if app.options[:size].nil?
      change_task_size(app.options[:cluster],
                       app.options[:size],
                       app.options[:service]) if continue?
    end

    app.add_action 'down', 'Change all service tasks to 0. Very Denger!!' do
      no_cluster_param if app.options[:cluster].nil?
      down(app.options[:cluster], app.options[:file]) if continue?
    end

    app.add_action 'up', 'Change all service tasks to N.' do
      no_cluster_param if app.options[:cluster].nil?
      no_file_param if app.options[:file].nil?
      up(app.options[:cluster], app.options[:file]) if continue?
    end

    app.add_option 'c CLUSTERNAME', 'cluster CLUSTERNAME', 'Specifies the ECS cluster name.'
    app.add_option 's [SERVICENAME]', 'service [SERVICENAME]', 'Specifies the service name.'
    app.add_option '', 'size [TASKSIZE]', 'Specifies the number of tasks to maintain in your cluster.'
    app.add_option '', 'json', 'Output JSON format.'
    app.add_option 'f [JSONFILENAME]', 'file [JSONFILENAME]', 'Specifies the JSON file name.'

    app.run ARGV
  end

  def version
    puts VERSION
  end

  def no_cluster_param
    puts '`--cluster` parameter is not set!!'
    exit 1 
  end

  def no_file_param
    puts '`--file` parameter is not set!!'
    exit 1 
  end

  def no_size_param
    puts '`--size` parameter is not set!!'
    exit 1 
  end

  def no_services(cluster)
    puts "no services in the `#{cluster}`."
    exit 0
  end

  def ecs
    ecs ||= Aws::ECS::Client.new
  end

  def asg
    asg ||= Aws::ApplicationAutoScaling::Client.new
  end

  def continue?(prompt = 'Do you want to continue?:', default = true)
    ans = ''
    d = default ? 'y' : 'n'
    until %w[y n].include?(ans)
      ans = ask("Do you want to continue?: [Y/n] ") { |q| q.limit = 1; q.case = :downcase }
      ans = d if ans.length == 0
    end
    ans == 'y'
  end

  def output_json(rules)
    puts JSON.pretty_generate(rules)
    exit 0
  end

  def output(rules, json)
    output_json(rules) if json
    headers = rules.first.keys
    rows = []
    rules.each do |rule|
      rows << rule.values
    end
    table = Terminal::Table.new :headings => headers, :rows => rows

    puts table
  end

  def find_services(cluster)
    resp = ecs.list_services(cluster: cluster)
    services = resp.service_arns.map { |arn| arn.split("/").last }
    no_services(cluster) if services.empty?
    services
  end

  def describe_services_per_cluster(cluster)
    services = find_services(cluster)
    min_caps = describe_min_capacity(cluster)
    resp = ecs.describe_services({
      cluster: cluster,
      services: services
    })

    svs = []
    resp.services.each do |s|
      sv = { 'Name': s.service_name,
             'Task': s.task_definition.to_resource_name,
             'Desired': s.desired_count,
             'Running': s.running_count,
             'Status': s.status }
      sv['MinCap'] = min_caps.cap_value(s.service_name) ? min_caps.cap_value(s.service_name) : ""
      svs << sv
    end
    svs
  end

  def describe_min_capacity(cluster)
    targets = []
    loop do
      resp = asg.describe_scalable_targets({
        service_namespace: "ecs"
      })
      resp.scalable_targets.each do |t|
        targets << { 'Name': t.resource_id.to_resource_name,
                     'ResourceId': t.resource_id,
                     'MinCap': t.min_capacity } if t.resource_id.include?(cluster)
      end
      break if resp.next_token.nil?
    end
    targets
  end

  def change_task_size(cluster, size, sv = nil)
    services = find_services(cluster) if sv.nil?
    services = sv.split unless sv.nil?
    services.each do |s|
      puts "Change desired size of tasks in #{s} to #{size}."
      begin
        ecs.update_service({
          cluster: cluster,
          desired_count: size, 
          service: s, 
        })
        puts "Changed."
      rescue Aws::ECS::Errors::ServiceNotFoundException
        puts "Got error. Reason: #{sv} Service Not Found."
      rescue Aws::ECS::Errors::ServiceError => ex
        puts "Got error. Reason: #{ex}"
      end
    end
  end

  def change_capacity_size(size, resource_id)
    puts "Change capacity size of #{resource_id} to #{size}."
    begin
      asg.register_scalable_target({
        min_capacity: size, 
        resource_id: resource_id,
        scalable_dimension: 'ecs:service:DesiredCount',
        service_namespace: 'ecs',
      })
      puts "Changed."
    rescue Aws::ApplicationAutoScaling::Errors::ServiceError => ex
      puts "Got error. Reason: #{ex}"
    end
  end

  def down(cluster, file = nil)
    # ファイルが引数として渡された場合 (指定したサービス毎に Desire Count を 0 にする)
    services = File.open(file) { |j| JSON.load(j) } unless file.nil?
    services.each do |s|
      change_task_size(cluster, 0, s['Name'])
    end unless file.nil?
    # ファイルが引数として渡されなかった場合 (全サービスの Desire Count を 0 にする)
    change_task_size(cluster, 0) if file.nil?
 
    # Cluster に定義されている AutoScaling の情報を取得
    targets = describe_min_capacity(cluster)
    # Cluster に定義されている service の AutoScaling minimum capacity を 0 に変更する
    targets.each do |t|
      change_capacity_size(0, t[:ResourceId])
    end unless targets.empty?
  end

  def up(cluster, file)
    services = File.open(file) { |j| JSON.load(j) }
    services.each do |s|
      unless s['MinCap'] == ""
        change_capacity_size(s['MinCap'], "service/#{cluster}/#{s['Name']}")
        change_task_size(cluster, s['MinCap'], s['Name'])
      end
      change_task_size(cluster, s['Desired'], s['Name']) if s['MinCap'] == ""
    end
  end

  Tsumikata.new.run
end
