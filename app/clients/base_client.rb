class BaseClient
  class ApiError < StandardError
    attr_reader :status, :body, :upstream

    def initialize(message, status: nil, body: nil, upstream: nil)
      super(message)
      @status = status
      @body = body
      @upstream = upstream
    end
  end

  class ConnectionError < ApiError; end
  class TimeoutError < ApiError; end
  class ClientError < ApiError; end
  class ServerError < ApiError; end
  class UnauthorizedError < ClientError; end
  class NotFoundError < ClientError; end

  def initialize(base_url:, timeout: 30, open_timeout: 5)
    @base_url = base_url
    @timeout = timeout
    @open_timeout = open_timeout
  end

  private

  def connection
    @connection ||= Faraday.new(url: @base_url) do |f|
      f.request :json
      f.response :json
      f.request :retry, max: 2, interval: 0.5, exceptions: [Faraday::ServerError, Faraday::TimeoutError]
      f.options.timeout = @timeout
      f.options.open_timeout = @open_timeout
      f.adapter Faraday.default_adapter
    end
  end

  def handle_response(response)
    case response.status
    when 200..299
      response
    when 401
      raise UnauthorizedError.new("Unauthorized", status: response.status, body: response.body)
    when 404
      raise NotFoundError.new("Not found", status: response.status, body: response.body)
    when 400..499
      raise ClientError.new("Client error: #{response.status}", status: response.status, body: response.body)
    when 500..599
      raise ServerError.new("Server error: #{response.status}", status: response.status, body: response.body)
    else
      raise ApiError.new("Unexpected status: #{response.status}", status: response.status, body: response.body)
    end
  end

  def get(path, params: {}, headers: {})
    response = connection.get(path, params, headers)
    handle_response(response)
  rescue Faraday::TimeoutError => e
    raise TimeoutError.new("Request timed out", upstream: e)
  rescue Faraday::ConnectionFailed => e
    raise ConnectionError.new("Connection failed", upstream: e)
  end

  def post(path, body: {}, headers: {})
    response = connection.post(path, body, headers)
    handle_response(response)
  rescue Faraday::TimeoutError => e
    raise TimeoutError.new("Request timed out", upstream: e)
  rescue Faraday::ConnectionFailed => e
    raise ConnectionError.new("Connection failed", upstream: e)
  end

  def put(path, body: {}, headers: {})
    response = connection.put(path, body, headers)
    handle_response(response)
  rescue Faraday::TimeoutError => e
    raise TimeoutError.new("Request timed out", upstream: e)
  rescue Faraday::ConnectionFailed => e
    raise ConnectionError.new("Connection failed", upstream: e)
  end

  def delete(path, headers: {})
    response = connection.delete(path, nil, headers)
    handle_response(response)
  rescue Faraday::TimeoutError => e
    raise TimeoutError.new("Request timed out", upstream: e)
  rescue Faraday::ConnectionFailed => e
    raise ConnectionError.new("Connection failed", upstream: e)
  end
end
