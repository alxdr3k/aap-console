module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user_sub

    def connect
      self.current_user_sub = find_user_sub
      reject_unauthorized_connection unless current_user_sub.present?
    end

    private

    # ActionCable connections do not run the controller request lifecycle, so
    # `request.session` is not reliable here. The Console uses Rails' default
    # cookie-based session store, so we decrypt the session cookie directly
    # by its configured key. The previous implementation gated on the
    # presence of an `_session_id` cookie that Rails never sets, which
    # silently dropped every authenticated WebSocket attempt.
    def find_user_sub
      session_data = decoded_session
      return nil unless session_data.is_a?(Hash)
      session_data["user_sub"] || session_data[:user_sub]
    end

    def decoded_session
      key = Rails.application.config.session_options[:key]
      return nil if key.blank?
      cookies.encrypted[key]
    end
  end
end
