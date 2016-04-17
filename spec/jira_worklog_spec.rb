require 'spec_helper'
require_relative '../bin/jira_worklog'

describe '#add_time' do
  before :each do
    allow(STDOUT).to receive(:puts)
  end

  it 'should raise if issue does not exist' do
    stub_request(
        :post,
        'https://alex:password@jira.example.com/rest/api/2/issue/DEV-123/worklog'
      ).
      with(:body    => "{\"started\":\"2016-04-16T09:00:00.000+1000\",\"timeSpentSeconds\":1800}",
           :headers => {
             "Accept"=>"*/*; q=0.5, application/xml",
             "Accept-Encoding"=>"gzip",
             "Content-Length"=>"66",
             "Content-Type"=>"application/json",
             "User-Agent"=>"unirest-ruby/1.1"
           }
      ).
      to_return(:status  => 404,
                :body    => 'Issue Does Not Exist',
                :headers => {}
      )
    expect { add_time('DEV-123', '2016-04-16', 1800, {
      'server'      => 'jira.example.com',
      'username'    => 'alex',
      'password'    => 'password',
      'time_string' => 'T09:00:00.000+1000',
    }) }.to raise_error(RuntimeError, /Failed adding to worklog in DEV-123 for 2016-04-16/)
  end

  it 'should raise if issue does not exist' do
    stub_request(
        :post,
        'https://alex:password@jira.example.com/rest/api/2/issue/DEV-123/worklog'
      ).
      with(:body    => "{\"started\":\"2016-04-16T09:00:00.000+1000\",\"timeSpentSeconds\":1800}",
           :headers => {
             "Accept"=>"*/*; q=0.5, application/xml",
             "Accept-Encoding"=>"gzip",
             "Content-Length"=>"66",
             "Content-Type"=>"application/json",
             "User-Agent"=>"unirest-ruby/1.1"
           }
      ).
      to_return(:status  => 201,
                :body    => 'Updated',
                :headers => {}
      )
    expect(add_time('DEV-123', '2016-04-16', 1800, {
      'server'      => 'jira.example.com',
      'username'    => 'alex',
      'password'    => 'password',
      'time_string' => 'T09:00:00.000+1000',
    })).to be_nil
  end
end

describe '#get_config' do
  it 'should emit an error if file is not found' do
    expect { get_config('/some/file') }.to raise_error(/No such file or directory/)
  end

  it 'should emit an error if a badly formatted time_string is given' do
    allow(YAML).to receive(:load_file).with('/some/file').and_return({'server'=>'jira.example.com', 'username'=>'fred', 'infill'=>'8h', 'time_string'=>'I_am_bad'})
    expect { get_config('/some/file') }.to raise_error(RuntimeError, /Syntax error in config file/)
  end

  it 'should emit an error if infill is badly formatted' do
    allow(YAML).to receive(:load_file).with('/some/file').and_return({'server'=>'jira.example.com', 'username'=>'fred', 'infill'=>'I_am_bad'})
    expect { get_config('/some/file') }.to raise_error(RuntimeError, /Syntax error in config file/)
  end

  it 'should set a default of 8h if no infill is given' do
    allow(YAML).to receive(:load_file).with('/some/file').and_return({'server'=>'jira.example.com', 'username'=>'fred'})
    allow_any_instance_of(Object).to receive(:get_password).and_return('password')
    expect(get_config('/some/file')).to include('infill'=>'8h')
  end
end

describe '#write_state and #get_state' do
  it 'should write an array and read it back from disk' do
    write_state(['2016-04-12', '2016-04-13'], 'state_file.tmp')
    expect(get_state('state_file.tmp')).to match_array(['2016-04-12', '2016-04-13'])
    File.delete('state_file.tmp')
  end

  it 'should correctly push dates to the end of an array' do
    state = ['2016-04-12', '2016-04-13']
    state.push('2016-04-14')
    expect(state).to match_array(['2016-04-12', '2016-04-13', '2016-04-14'])
  end
end 

describe '#get_data' do
  it 'should emit an error if file is not found' do
    expect { get_data('/some/file') }.to raise_error(/No such file or directory/)
  end

  it 'should emit an error if Hash contains no worklog' do
    allow(YAML).to receive(:load_file).with('/some/file').and_return('default'=>'BKR-723')
    expect { get_data('/some/file') }.to raise_error(RuntimeError, /No worklog found in data file/)
  end

  it 'should emit an error if worklog is not a Hash' do
    allow(YAML).to receive(:load_file).with('/some/file').and_return('default'=>'BKR-723', 'worklog'=>['I','am','not','a','hash'])
    expect { get_data('/some/file') }.to raise_error(RuntimeError, /Expected worklog to be a Hash of Hashes of Arrays/)
  end

  it 'should emit an error given a non ISO date in worklog' do
    allow(YAML).to receive(:load_file).with('/some/file').and_return('default'=>'BKR-723', 'worklog'=>{'I_am_not_a_date'=>['MODULES-3125:4h']})
    expect { get_data('/some/file') }.to raise_error(RuntimeError, /Expected dates in worklog to be in ISO date format/)
  end

  it 'should emit an error given badly formatted Jira ticket in worklog' do
    allow(YAML).to receive(:load_file).with('/some/file').and_return({'default'=>'BKR-723', 'worklog'=>{'2016-04-14'=>['I_am_not_a_jira:4h']}})
    expect { get_data('/some/file') }.to raise_error(RuntimeError, /Syntax error in Worklog/)
  end

  it 'should emit an error given time entry 8 30m' do
    allow(YAML).to receive(:load_file).with('/some/file').and_return({'default'=>'BKR-723', 'worklog'=>{'2016-04-14'=>['MODULES-3125:8 3m']}})
    expect { get_data('/some/file') }.to raise_error(RuntimeError, /Syntax error in Worklog/)
  end

  it 'should emit an error given time entry 8.5' do
    allow(YAML).to receive(:load_file).with('/some/file').and_return({'default'=>'BKR-723', 'worklog'=>{'2016-04-14'=>['MODULES-3125:8.5']}})
    expect { get_data('/some/file') }.to raise_error(RuntimeError, /Syntax error in Worklog/)
  end

  it 'should accept time as 1h 30m' do
    allow(YAML).to receive(:load_file).with('/some/file').and_return({'worklog'=>{'2016-04-14'=>['MODULES-3125:1h 30m']}})
    expect(get_data('/some/file')).to include({'worklog'=>{'2016-04-14'=>['MODULES-3125:1h 30m']}})
  end

  it 'should accept time as 30m' do
    allow(YAML).to receive(:load_file).with('/some/file').and_return({'worklog'=>{'2016-04-14'=>['MODULES-3125:30m']}})
    expect(get_data('/some/file')).to include({'worklog'=>{'2016-04-14'=>['MODULES-3125:30m']}})
  end

  it 'should accept time as 8h' do
    allow(YAML).to receive(:load_file).with('/some/file').and_return({'worklog'=>{'2016-04-14'=>['MODULES-3125:8h']}})
    expect(get_data('/some/file')).to include({'worklog'=>{'2016-04-14'=>['MODULES-3125:8h']}})
  end

  it 'should accept time as 8 for 8h' do
    allow(YAML).to receive(:load_file).with('/some/file').and_return({'worklog'=>{'2016-04-14'=>['MODULES-3125:8']}})
    expect(get_data('/some/file')).to include({'worklog'=>{'2016-04-14'=>['MODULES-3125:8']}})
  end
end

describe '#s2hm' do
  it 'should convert 7320 seconds to 2h 2m' do
    expect(s2hm(7320)).to eql '2h 2m'
  end

  it 'should convert 28800 seconds to 8h 0m' do
    expect(s2hm(28800)).to eql '8h 0m'
  end

  it 'should convert 1800 seconds to 0h 30m' do
    expect(s2hm(1800)).to eql '0h 30m'
  end

  it 'should convert 12345660 seconds to 3429h 21m' do
    expect(s2hm(12345660)).to eql '3429h 21m'
  end

  it 'should convert 131 seconds to 0h 2m (i.e. loses extra seconds)' do
    expect(s2hm(131)).to eql '0h 2m'
  end
end

describe '#hm2s' do
  it 'should convert 2h 2m to 7320 seconds' do
    expect(hm2s('2h 2m')).to eq 7320
  end

  it 'should convert 8h to 28800 seconds' do
    expect(hm2s('8h')).to eq 28800
  end

  it 'should convert 8 to 28800 seconds' do
    expect(hm2s('8')).to eq 28800
  end

  it 'should convert 30m to 1800 seconds' do
    expect(hm2s('30m')).to eq 1800
  end

  it 'should convert 3429h 21m to 12345660 seconds' do
    expect(hm2s('3429h 21m')).to eq 12345660
  end
end
