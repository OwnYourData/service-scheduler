#!/usr/bin/env ruby
# encoding: utf-8

require 'optparse'
require 'httparty'
require 'rufus-scheduler'
require 'bunny'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"
  opts.on('-u', '--PIA_URL URL', 'Data Vault URL') { 
  	|v| options[:pia_url] = v }
  opts.on('-k', '--APP_KEY KEY', 'Scheduler Application Key') { 
  	|v| options[:app_key] = v }
  opts.on('-s', '--APP_SECRET SECRET', 'Scheduler Application Secret') { 
  	|v| options[:app_secret] = v }
end.parse!

def defaultHeaders(token)
  { 'Accept' => '*/*',
    'Content-Type' => 'application/json',
    'Authorization' => 'Bearer ' + token }
end

def getToken(pia_url, app_key, app_secret)
  auth_url = pia_url + '/oauth/token'
  auth_credentials = { username: app_key, 
                       password: app_secret }
  response = HTTParty.post(auth_url,
                           basic_auth: auth_credentials,
                           body: { grant_type: 'client_credentials' })
  token = response.parsed_response["access_token"]
  if token.nil?
      nil
  else
      token
  end
end

def setupApp(pia_url, app_key, app_secret)
  token = getToken(pia_url, app_key, app_secret)
  { "pia_url"    => pia_url,
    "app_key"    => app_key,
    "app_secret" => app_secret,
    "token"      => token }
end

def writeLog(app, message)
  url = app["pia_url"] + '/api/logs/create'
  headers = defaultHeaders(app["token"])
  data = { 
  	identifier: "oyd.scheduler",
  	log: message }.to_json
  response = HTTParty.post(url,
                           headers: headers,
                           body: data)
end

# setup queue
conn = Bunny.new(host:  ENV["QUEUE_HOST"], 
				 vhost: ENV["QUEUE_VHOST"],
				 user:  ENV["QUEUE_USER"],
				 pass:  ENV["QUEUE_PWD"])
conn.start
ch = conn.create_channel
q = ch.queue(ENV["QUEUE_NAME"])

# sa - scheduler_application
sa = setupApp(options[:pia_url], 
		      options[:app_key],
		      options[:app_secret])

# get list of active tasks
headers = defaultHeaders(sa["token"])
url_data = options[:pia_url] + '/api/tasks/active'
response = HTTParty.get(url_data,
						headers: headers)
response_parsed = response.parsed_response

url_app_data = options[:pia_url] + '/api/apps/'
url_update_task = options[:pia_url] + '/api/tasks/'
response_parsed.each do |task|
	plugin_id = task['plugin_id']
	writeLog(sa,
		     'start ' + task['identifier'] + 
		     ' for plugin ' + plugin_id.to_s)

	if plugin_id.nil?
		ta = sa
		task_app_key = options[:app_key]
		task_app_secret = options[:app_secret]
	else
		# get infos about respective Plugin
		response = HTTParty.get(url_app_data + plugin_id.to_s,
								headers: headers)
		task_app_key = response.parsed_response.first['uid'].to_s
		task_app_secret = response.parsed_response.first['secret'].to_s
		# ta - application for respective task
		ta = setupApp(options[:pia_url],
					  task_app_key,
					  task_app_secret)
	end

	# replace PIA_URL, APP_KEY, APP_SECRET and write into queue
	task_command = Base64.decode64(task['command'].delete("\n")).rstrip
	task_command = task_command.gsub('[PIA_URL]', options[:pia_url])
	task_command = task_command.gsub('[APP_KEY]', task_app_key)
	task_command = task_command.gsub('[APP_SECRET]', task_app_secret)
	ch.default_exchange.publish(task_command, routing_key: q.name)

	# check if it is a one-time job
	if task['schedule'] == 'delete'
		task_delete_url = options[:pia_url] + '/api/tasks/' + task['id'].to_s
		response = HTTParty.delete(task_delete_url,
								   headers: headers)
	else
		# set run_next timestamp
		next_time = Rufus::Scheduler.parse(task['schedule'])
			.next_time.utc.strftime("%Y-%m-%dT%H:%M:%S")
		data = { next_run: next_time }
		task_headers = defaultHeaders(ta["token"])
		response = HTTParty.put(url_update_task + task['identifier'],
			                    headers: task_headers,
			                    body: data.to_json)
	end
	writeLog(sa,
		     'finished ' + task['identifier'] + 
			 ' for plugin ' + plugin_id.to_s + 
			 ' with response ' + response.code.to_s)
end