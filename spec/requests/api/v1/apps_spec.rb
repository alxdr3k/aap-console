require "rails_helper"

RSpec.describe "Api::V1::Apps", type: :request do
  let!(:org) { create(:organization) }
  let!(:project) { create(:project, :active, organization: org) }

  describe "GET /api/v1/apps" do
    context "with valid API key" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("CONSOLE_INBOUND_API_KEY").and_return("test-inbound-key")
      end

      it "returns 200 with all apps" do
        get "/api/v1/apps", params: { all: true },
            headers: { "Authorization" => "Bearer test-inbound-key" }
        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)
        expect(data).to have_key("apps")
      end
    end

    context "with invalid API key" do
      it "returns 401" do
        get "/api/v1/apps", params: { all: true },
            headers: { "Authorization" => "Bearer wrong-key" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "without Authorization header" do
      it "returns 401" do
        get "/api/v1/apps", params: { all: true }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
