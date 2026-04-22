module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user_sub

    def connect
      self.current_user_sub = session[:user_sub]
      reject_unauthorized_connection unless current_user_sub.present?
    end

    private

    def session
      @session ||= cookies.encrypted[:_session_id] ? {} : request.session
    end
  end
end
