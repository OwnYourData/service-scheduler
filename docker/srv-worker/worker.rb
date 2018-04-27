#!/usr/bin/env ruby
# encoding: utf-8

require 'bunny'
require 'json'

# TODO: add option to pass input with config options (private key, credentials)
config = nil

conn = Bunny.new(host:  ENV["QUEUE_HOST"], 
                 vhost: ENV["QUEUE_VHOST"],
                 user:  ENV["QUEUE_USER"],
                 pass:  ENV["QUEUE_PWD"],
                 automatically_recover: false)
conn.start
ch = conn.create_channel
q = ch.queue(ENV["QUEUE_NAME"])

begin
  puts " [*] Waiting for messages. To exit press CTRL+C"
  q.subscribe(:block => true) do |delivery_info, properties, body|
    cmd = body #.gsub("\n", ' ').gsub("\r", ' ').gsub("\\", ' ')
    if !config.nil? && config.length > 0
      config.each do |val|
      	cmd = cmd.gsub('[' + val[0].upcase + ']', val[1].to_s)
      end
    end
    puts " [x] " + Time.now.to_s  + " execute command:\n#{cmd}"
    system "bash", "-c", cmd
    exit_status = $?.exitstatus
    if exit_status == 0
    	puts " [x] successfully executed command"
    else
    	puts " [o] command terminated with error " + exit_status.to_s
    end

  end
rescue Interrupt => _
  conn.close

  exit(0)
end