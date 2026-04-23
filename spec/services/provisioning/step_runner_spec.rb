require "rails_helper"

RSpec.describe Provisioning::StepRunner do
  let(:project) { create(:project) }
  let(:job) { create(:provisioning_job, :in_progress, project: project) }
  let(:step) do
    create(:provisioning_step,
           provisioning_job: job,
           name: "config_server_apply",
           step_order: 3,
           status: :pending,
           max_retries: 5)
  end

  describe "#execute retry behavior" do
    context "when backoff would exceed the inline-sleep ceiling" do
      it "returns :deferred without sleeping and schedules retry on the step" do
        step_impl = instance_double(Provisioning::Steps::ConfigServerApply)
        allow(step_impl).to receive(:already_completed?).and_return(false)
        allow(step_impl).to receive(:execute).and_raise("transient failure")

        runner = described_class.new(step: step, provisioning_job: job)
        allow(runner).to receive(:build_step_impl).and_return(step_impl)

        # Force the runner past the inline retry budget on the very first
        # failure by starting the attempt with enough prior retries that
        # the next backoff is > MAX_INLINE_RETRY_SLEEP.
        starting_retry = described_class::MAX_INLINE_RETRIES

        expect(runner).not_to receive(:sleep)
        result = runner.send(:attempt_execute, step_impl, retry_count: starting_retry)

        expect(result[:status]).to eq(:deferred)
        expect(result[:retry_in]).to be > described_class::MAX_INLINE_RETRY_SLEEP
        expect(step.reload.status).to eq("retrying")
      end
    end

    context "when backoff fits in the inline budget" do
      it "sleeps briefly and retries in the same worker call" do
        step_impl = instance_double(Provisioning::Steps::ConfigServerApply)
        allow(step_impl).to receive(:already_completed?).and_return(false)

        call_count = 0
        allow(step_impl).to receive(:execute) do
          call_count += 1
          raise "still down" if call_count == 1
          { "ok" => true }
        end

        runner = described_class.new(step: step, provisioning_job: job)
        allow(runner).to receive(:build_step_impl).and_return(step_impl)
        allow(runner).to receive(:sleep)

        result = runner.execute

        expect(result[:status]).to eq(:completed)
        expect(runner).to have_received(:sleep).at_least(:once)
      end
    end
  end
end
