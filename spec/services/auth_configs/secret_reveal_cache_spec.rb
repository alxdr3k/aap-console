require "rails_helper"

RSpec.describe AuthConfigs::SecretRevealCache do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :active, organization: organization) }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  it "writes and reads a client secret payload for the project" do
    described_class.write(project, key: "client_secret", label: "Client Secret", value: "kc-secret")

    payload = described_class.read(project)

    expect(payload.dig("secrets", "client_secret", "label")).to eq("Client Secret")
    expect(payload.dig("secrets", "client_secret", "value")).to eq("kc-secret")
    expect(payload["project_id"]).to eq(project.id)
  end

  it "returns an empty payload when cache metadata does not match the project" do
    other_project = create(:project, :active, organization: organization)

    Rails.cache.write(
      "auth-config-secret:#{project.id}",
      {
        "organization_id" => organization.id,
        "project_id" => other_project.id,
        "secrets" => {
          "client_secret" => { "label" => "Client Secret", "value" => "leaked" }
        }
      }
    )

    expect(described_class.read(project)["secrets"]).to eq({})
  end

  it "deletes a cached payload" do
    described_class.write(project, key: "client_secret", label: "Client Secret", value: "kc-secret")

    described_class.delete(project)

    expect(described_class.read(project)["secrets"]).to eq({})
  end
end
