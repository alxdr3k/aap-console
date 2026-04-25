require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:session_key) { Rails.application.config.session_options[:key] }

  it "identifies the connection from the decoded session" do
    allow_any_instance_of(described_class)
      .to receive(:decoded_session)
      .and_return("user_sub" => "kc-user-1")
    connect
    expect(connection.current_user_sub).to eq("kc-user-1")
  end

  it "supports symbol-keyed session data" do
    allow_any_instance_of(described_class)
      .to receive(:decoded_session)
      .and_return(user_sub: "kc-user-2")
    connect
    expect(connection.current_user_sub).to eq("kc-user-2")
  end

  it "rejects connections without a user_sub" do
    allow_any_instance_of(described_class)
      .to receive(:decoded_session)
      .and_return("other" => "value")
    expect { connect }.to have_rejected_connection
  end

  it "rejects connections with no session at all" do
    allow_any_instance_of(described_class)
      .to receive(:decoded_session)
      .and_return(nil)
    expect { connect }.to have_rejected_connection
  end

  describe "#decoded_session" do
    it "uses Rails.application.config.session_options[:key] as the cookie key" do
      conn = described_class.new(ActionCable.server, ActionDispatch::TestRequest.create.env)
      cookie_jar = double("cookie_jar")
      allow(conn).to receive(:cookies).and_return(double(encrypted: cookie_jar))
      expect(cookie_jar).to receive(:[]).with(session_key).and_return("user_sub" => "x")
      expect(conn.send(:decoded_session)).to eq("user_sub" => "x")
    end
  end
end
