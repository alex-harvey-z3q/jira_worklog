#!/usr/bin/env ruby

require 'json'
require 'yaml'
require 'highline'
require 'unirest'
require 'optparse'

##
# Adds time in seconds via Jira 7 REST API v2

def add_time(ticket, date, time_to_log_in_seconds, config, state, state_file)
  time_to_log = s2hm(time_to_log_in_seconds)
  puts "Adding #{time_to_log} to worklog in #{ticket} on #{date} ..."
  response = Unirest.post(
    "https://#{config['server']}/rest/api/2/issue/#{ticket}/worklog",
    headers: {
      'Content-Type' => 'application/json',
    },
    auth: {
      :user     => config['username'],
      :password => config['password'],
    },
    parameters: {
      'started'          => date + config['time_string'],
      'timeSpentSeconds' => time_to_log_in_seconds,
    }.to_json
  )
  unless response.code == 201
    write_state(state, state_file)
    raise "Failed adding to worklog in #{ticket} for #{date}:" +
          " returned #{response.code}: #{response.body.to_s}"
  end
end

##
# Converts hours and minutes to seconds.

def hm2s(hm)
  if hm =~ /\d+h +\d+m/
    h, m = /(\d+)h +(\d+)m/.match(hm).captures
    h.to_i * 60 * 60 + m.to_i * 60
  elsif hm =~ /\d+m/
    m = /(\d+)m/.match(hm).captures
    m[0].to_i * 60
  elsif hm =~ /\d+h?/
    h = /(\d+)h?/.match(hm).captures
    h[0].to_i * 60 * 60
  end
end

##
# Converts seconds to hours and minutes.

def s2hm(s)
  "%sh %sm" % [s / 3600, s / 60 % 60].map { |t| t.to_s }
end

##
# Returns the options from the command line.

def get_options
  options = OpenStruct.new
  options.config_file = File.join(Dir.home, '.jira_worklog/config.yml')
  options.data_file   = File.join(Dir.home, '.jira_worklog/data.yml')
  options.state_file  = File.join(Dir.home, '.jira_worklog/state.yml')
  opt_parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"
    opts.separator ''
    opts.separator 'Options:'
    opts.on('-f', '--datafile DATAFILE', String, 'data file with worklog data') do |v|
      options.data_file = v
    end
    opts.on('-c', '--configfile CONFIGFILE', String, 'file containing server, user name and infill') do |v|
      options.config_file = v
    end
  end
  opt_parser.parse!

  [options.config_file, options.data_file, options.state_file].each do |f|
    if !File.exist?(f)
      raise "File not found: #{f}"
    end
  end

  options
end

##
# Get a password from the command line.

def get_password
  cli = HighLine.new
  cli.ask('Enter your password: ') { |q| q.echo = false }
end

##
# Returns the YAML formatted config file as a Hash.
# +config_file+:: Path to the config file.

def get_config(config_file)
  config = YAML::load_file(config_file)

  # validate the config file.
  if !config.has_key?('time_string')
    config['time_string'] = 'T09:00:00.000+1000' # log all time as started 9am, AEDT
  end
  if config['time_string'] !~ /^T\d{2}:\d{2}:\d{2}\.\d{3}\+\d{4}$/
    raise "Syntax error in config file:" +
          " -----> time_string: #{config['time_string']} should be like " +
                                "T00:00:00.000+1000"
  end

  if !config.has_key?('infill')
    config['infill'] = '8h'
  end
  if config['infill'] !~ /\d+h(?: +\d+m)?/
    raise "Syntax error in config file:" +
          " -----> infill: #{config['infill']}"
  end

  unless config.has_key?('password')
    config['password'] = get_password
  end

  config
end

##
# Returns the YAML formatted data file as a Hash.

def get_data(data_file)
  data = YAML::load_file(data_file)

  # validate the worklog key.
  if !data.has_key?('worklog')
    raise "No worklog found in data file:" +
          " -----> #{data.to_s}"
  end
  if !data['worklog'].is_a?(Hash)
    raise "Expected worklog to be a Hash of Hashes of Arrays:" +
          " -----> #{data['worklog'].to_s} is not a Hash"
  end
  data['worklog'].each do |d, v|
    if d !~ /\d{4}-\d{2}-\d{2}/
      raise "Expected dates in worklog to be in ISO date format:" +
          " -----> #{d} in #{data['worklog'].to_s} is not in ISO date format"
    end
    if !v.is_a?(Array)
      raise "Expected worklog to be a Hash of Hashes of Arrays:"
          " -----> #{v} in #{data['worklog'].to_s} is not an Array"
    end
    v.each do |l|
      if l !~ /[A-Z]+-\d+:(?:\d+h?|\d+m|\d+h +\d+m)$/
        raise "Syntax error in Worklog:" +
          " -----> #{l} in #{data['worklog'].to_s}"
      end
    end
  end

  data
end

##
# Get the state from disk.

def get_state(state_file)
  YAML::load_file(state_file)
end

##
# Write the state back to disk.

def write_state(state, state_file)
  File.open(state_file, 'w') do |f|
    f.write state.to_yaml
  end
end

if $0 == __FILE__
  options = get_options

  data   = get_data(options.data_file)
  config = get_config(options.config_file)
  state  = get_state(options.state_file)

  data['worklog'].each do |date, values|
    next if state.has_key?(date) and state[date] == values
    state[date] = [] unless state.has_key?(date)
    total_seconds = 0
    values.each do |value|
      next if state.has_key?(date) and state[date].include?(value)
      ticket, hm = /(.*):(.*)/.match(value).captures
      add_time(ticket, date, hm2s(hm), config, state, options.state_file)
      state[date].push(value)
      total_seconds += hm2s(hm)
    end
    if data.has_key?('default')
      add_time(data['default'], date, (hm2s(config['infill']) - total_seconds),
               config, state, options.state_file)
    end
  end
  write_state(state, options.state_file)
end
