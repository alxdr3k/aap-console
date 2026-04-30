require "rails_helper"

RSpec.describe ProjectApiKeys::RevealCache do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :active, organization: organization) }
  let(:project_api_key) { create(:project_api_key, project: project, name: "staging-ci") }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  it "writes and reads a PAK reveal payload for the project" do
    described_class.write(project, project_api_key: project_api_key, token: "pak-secret-token")

    payload = described_class.read(project)

    expect(payload.dig("secrets", "project_api_key", "name")).to eq("staging-ci")
    expect(payload.dig("secrets", "project_api_key", "token_prefix")).to eq(project_api_key.token_prefix)
    expect(payload.dig("secrets", "project_api_key", "value")).to eq("pak-secret-token")
    expect(payload["project_id"]).to eq(project.id)
  end

  it "returns an empty payload when cache metadata does not match the project" do
    other_project = create(:project, :active, organization: organization)

    Rails.cache.write(
      "project-api-key-reveal:#{project.id}",
      {
        "organization_id" => organization.id,
        "project_id" => other_project.id,
        "secrets" => {
          "project_api_key" => { "label" => "Project API Key", "value" => "leaked" }
        }
      }
    )

    expect(described_class.read(project)["secrets"]).to eq({})
  end

  it "deletes a cached payload" do
    described_class.write(project, project_api_key: project_api_key, token: "pak-secret-token")

    described_class.delete(project)

    expect(described_class.read(project)["secrets"]).to eq({})
  end
end
