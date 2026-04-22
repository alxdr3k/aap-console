require "webmock/rspec"

# Block all real HTTP connections in tests
WebMock.disable_net_connect!(allow_localhost: true)
