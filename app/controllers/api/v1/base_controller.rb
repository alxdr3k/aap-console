module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_inbound_api_key!

      private

      def authenticate_inbound_api_key!
        token = extract_bearer_token
        expected = ENV["CONSOLE_INBOUND_API_KEY"]

        return if expected.present? && token.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)

        render json: { error: "Unauthorized" }, status: :unauthorized
      end

      def extract_bearer_token
        auth_header = request.headers["Authorization"]
        return nil unless auth_header&.start_with?("Bearer ")

        auth_header.sub("Bearer ", "")
      end
    end
  end
end
