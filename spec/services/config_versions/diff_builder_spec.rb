require "rails_helper"

RSpec.describe ConfigVersions::DiffBuilder do
  describe "#lines" do
    it "builds meta, removed, and added lines from snapshot JSON" do
      lines = described_class.new(
        before_snapshot: { models: [ "claude-sonnet" ], s3_retention_days: 90 },
        after_snapshot: { models: [ "claude-sonnet", "azure-gpt4" ], s3_retention_days: 120 },
        before_label: "v0",
        after_label: "v1"
      ).lines

      expect(lines.first.text).to eq("--- v0")
      expect(lines.second.text).to eq("+++ v1")
      expect(lines.map(&:text)).to include('-   "s3_retention_days": 90')
      expect(lines.map(&:text)).to include('+   "s3_retention_days": 120')
      expect(lines.map(&:text)).to include('+     "azure-gpt4"')
    end
  end
end
