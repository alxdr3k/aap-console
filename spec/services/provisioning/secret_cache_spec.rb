require "rails_helper"

RSpec.describe Provisioning::SecretCache do
  include ActiveSupport::Testing::TimeHelpers

  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:project) { create(:project) }
  let(:job) { create(:provisioning_job, :completed, project: project) }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  it "stores generated secrets with project authorization metadata" do
    described_class.write(job, key: "client_secret", label: "Client Secret", value: "kc-secret")

    payload = described_class.read(job)

    expect(payload.dig("secrets", "client_secret", "label")).to eq("Client Secret")
    expect(payload.dig("secrets", "client_secret", "value")).to eq("kc-secret")
    expect(payload["expires_at"]).to be_present
  end

  it "merges multiple secrets for the same provisioning job" do
    described_class.write(job, key: "client_secret", label: "Client Secret", value: "kc-secret")
    described_class.write(job, key: "pak", label: "Project API Key", value: "pak-secret")

    payload = described_class.read(job)

    expect(payload.fetch("secrets").keys).to contain_exactly("client_secret", "pak")
  end

  it "deletes a cached reveal payload by provisioning job id" do
    described_class.write(job, key: "client_secret", label: "Client Secret", value: "kc-secret")

    described_class.delete(job.id)

    expect(described_class.read(job)).to eq({})
  end

  it "ignores cache entries whose project metadata does not match the job" do
    cache.write(
      described_class.cache_key(job.id),
      {
        "organization_id" => project.organization_id,
        "project_id" => -1,
        "secrets" => {
          "client_secret" => { "label" => "Client Secret", "value" => "leaked" }
        }
      }
    )

    expect(described_class.read(job)).to eq({})
  end

  it "expires cached secrets after the reveal TTL" do
    described_class.write(job, key: "client_secret", label: "Client Secret", value: "kc-secret")

    travel described_class::TTL + 1.second do
      expect(described_class.read(job)).to eq({})
    end
  end
end
