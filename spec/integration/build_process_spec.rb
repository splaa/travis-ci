require 'spec_helper'

feature 'The build process' do
  include Rack::Test::Methods

  before(:each) do
    Travis.config.notifications = [:worker, :pusher]
  end

  scenario 'creates a request from a github payload, configures it, creates the build and runs the tests (multiple tests matrix)', :driver => :rack_test do
    ping_from_github!

    _request.should be_created
    pusher.should have_message('build:queued') # TODO legacy. should be job:configure:created
    job.should be_queued

    worker.start!(job, 'started_at' => Time.now)
    # pusher.should have_message('job:configure:started') # not currently used.

    worker.finish!(job, 'config' => { 'rvm' => ['1.8.7', '1.9.2'] })

    _request.should be_finished
    build.should be_created
    pusher.should have_message('build:removed')

    job.should_not be_queued
    build.matrix.each { |job| job.should be_queued }
    api.repositories.should_not include(json_for_http(repository))

    while next_job!
      worker.start!(job, 'started_at' => Time.now)

      job.should be_started
      build.should be_started
      pusher.should have_message('build:started')

      api.repositories.should include(json_for_http(repository))
      # api.build(build).should include(json_for_http(build)) # TODO
      # api.job(job).should include(json_for_http(job))    # TODO

      worker.log!(job, 'log' => 'foo')
      job.log.should == 'foo'
      pusher.should have_message('build:log', :log => 'foo')

      worker.finish!(job, 'finished_at' => Time.now, 'status' => 0, 'log' => 'foo bar')
      job.should be_finished
      pusher.should have_message('build:finished')
      # api.job(job).should include(json_for_http(job)) # TODO
    end

    build.reload.should be_finished
    build.status.should == 0
    # api.build(build).should include(json_for_http(build)) # TODO

    repository.should have_last_build(build)
    api.repositories.should include(json_for_http(repository))

    pusher.should have_message('build:finished')
  end
end
