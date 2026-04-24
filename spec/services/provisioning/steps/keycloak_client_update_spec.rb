require "rails_helper"

RSpec.describe Provisioning::Steps::KeycloakClientUpdate do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :active, organization: organization) }
  let(:job) { create(:provisioning_job, :update, project: project) }

  def build_step(params: {}, result_snapshot: nil)
    step_record = create(:provisioning_step, :keycloak_client_update,
                         provisioning_job: job, result_snapshot: result_snapshot)
    described_class.new(step_record: step_record, project: project, params: params)
  end

  describe "#execute" do
    context "when no auth_config exists" do
      it "skips without calling Keycloak" do
        step = build_step(params: { redirect_uris: [ "https://example.com/cb" ] })
        result = step.execute
        expect(result[:skipped]).to be(true)
        expect(a_request(:any, //)).not_to have_been_made
      end
    end

    context "when auth_type is pak" do
      let!(:auth_config) { create(:project_auth_config, :pak, project: project) }

      it "skips without calling Keycloak" do
        step = build_step(params: { redirect_uris: [ "https://example.com/cb" ] })
        result = step.execute
        expect(result[:skipped]).to be(true)
        expect(a_request(:any, //)).not_to have_been_made
      end
    end

    context "when no auth_config params are present" do
      let!(:auth_config) { create(:project_auth_config, :oidc, project: project) }

      it "skips without calling Keycloak" do
        step = build_step(params: { models: [ "gpt-4" ] })
        result = step.execute
        expect(result[:skipped]).to be(true)
        expect(a_request(:any, //)).not_to have_been_made
      end
    end

    context "when redirect_uris are provided" do
      let!(:auth_config) do
        create(:project_auth_config, :oidc, project: project,
               redirect_uris: [ "https://old.example.com/cb" ],
               post_logout_redirect_uris: [ "https://old.example.com" ])
      end

      let(:uuid) { auth_config.keycloak_client_uuid }
      let(:client_id) { auth_config.keycloak_client_id }

      before do
        stub_keycloak_get_clients(client_id: client_id,
                                  clients: [ { "id" => uuid, "clientId" => client_id,
                                               "redirectUris" => [ "https://old.example.com/cb" ] } ])
        stub_keycloak_update_client(uuid: uuid)
      end

      it "calls Keycloak update_client" do
        step = build_step(params: { redirect_uris: [ "https://new.example.com/cb" ] })
        step.execute
        expect(a_request(:put, /clients\/#{uuid}/)).to have_been_made
      end

      it "persists new redirect_uris to project_auth_config DB after Keycloak succeeds" do
        step = build_step(params: { redirect_uris: [ "https://new.example.com/cb" ] })
        step.execute
        expect(auth_config.reload.redirect_uris).to eq([ "https://new.example.com/cb" ])
      end

      it "persists new post_logout_redirect_uris to DB when provided" do
        step = build_step(params: {
          redirect_uris: [ "https://new.example.com/cb" ],
          post_logout_redirect_uris: [ "https://new.example.com" ]
        })
        step.execute
        config = auth_config.reload
        expect(config.redirect_uris).to eq([ "https://new.example.com/cb" ])
        expect(config.post_logout_redirect_uris).to eq([ "https://new.example.com" ])
      end

      it "does not overwrite unchanged fields (redirect_uris not in params)" do
        step = build_step(params: { post_logout_redirect_uris: [ "https://new-logout.example.com" ] })
        step.execute
        expect(auth_config.reload.redirect_uris).to eq([ "https://old.example.com/cb" ])
      end

      it "snapshots previous DB values so rollback can restore them" do
        step = build_step(params: { redirect_uris: [ "https://new.example.com/cb" ] })
        result = step.execute
        expect(result[:previous_redirect_uris]).to eq([ "https://old.example.com/cb" ])
        expect(result[:previous_post_logout_redirect_uris]).to eq([ "https://old.example.com" ])
      end

      it "returns updated: true with the keycloak_client_uuid" do
        step = build_step(params: { redirect_uris: [ "https://new.example.com/cb" ] })
        result = step.execute
        expect(result[:updated]).to be(true)
        expect(result[:keycloak_client_uuid]).to eq(uuid)
      end

      it "persists the side-effect snapshot to the step before raising when the local DB write fails" do
        allow_any_instance_of(ProjectAuthConfig).to receive(:update!).and_raise(
          ActiveRecord::RecordInvalid.new(ProjectAuthConfig.new)
        )

        step_record = create(:provisioning_step, :keycloak_client_update, provisioning_job: job)
        step = described_class.new(step_record: step_record, project: project,
                                   params: { redirect_uris: [ "https://new.example.com/cb" ] })

        expect { step.execute }.to raise_error(ActiveRecord::RecordInvalid)

        step_record.reload
        expect(step_record.result_snapshot).to include(
          "updated" => true,
          "local_persisted" => false,
          "keycloak_client_uuid" => uuid,
          "previous_redirect_uris" => [ "https://old.example.com/cb" ]
        )
      end
    end

    context "resume path (snapshot with updated: true but local_persisted: false)" do
      let!(:auth_config) do
        create(:project_auth_config, :oidc, project: project,
               redirect_uris: [ "https://old.example.com/cb" ],
               post_logout_redirect_uris: [ "https://old.example.com" ])
      end

      let(:uuid) { auth_config.keycloak_client_uuid }

      it "re-runs local DB update without re-calling Keycloak" do
        step_record = create(:provisioning_step, :keycloak_client_update, provisioning_job: job,
                             result_snapshot: {
                               "updated" => true,
                               "local_persisted" => false,
                               "keycloak_client_uuid" => uuid,
                               "previous_state" => { "id" => uuid,
                                                     "clientId" => auth_config.keycloak_client_id },
                               "previous_redirect_uris" => [ "https://old.example.com/cb" ],
                               "previous_post_logout_redirect_uris" => [ "https://old.example.com" ]
                             })

        step = described_class.new(step_record: step_record, project: project,
                                   params: { redirect_uris: [ "https://new.example.com/cb" ] })

        result = step.execute

        expect(a_request(:put, /clients/)).not_to have_been_made
        expect(a_request(:get, /clients/)).not_to have_been_made
        expect(auth_config.reload.redirect_uris).to eq([ "https://new.example.com/cb" ])
        expect(result["local_persisted"]).to be(true)
      end
    end
  end

  describe "#already_completed?" do
    let!(:auth_config) { create(:project_auth_config, :oidc, project: project) }

    it "returns false when snapshot has updated: true but local_persisted: false" do
      step_record = create(:provisioning_step, :keycloak_client_update, provisioning_job: job,
                           result_snapshot: { "updated" => true, "local_persisted" => false,
                                              "keycloak_client_uuid" => auth_config.keycloak_client_uuid })
      step = described_class.new(step_record: step_record, project: project, params: {})
      expect(step.already_completed?).to be(false)
    end

    it "returns true only when both updated and local_persisted are true" do
      step_record = create(:provisioning_step, :keycloak_client_update, provisioning_job: job,
                           result_snapshot: { "updated" => true, "local_persisted" => true,
                                              "keycloak_client_uuid" => auth_config.keycloak_client_uuid })
      step = described_class.new(step_record: step_record, project: project, params: {})
      expect(step.already_completed?).to be(true)
    end

    it "still returns true for skipped snapshots (no external work to gate)" do
      step_record = create(:provisioning_step, :keycloak_client_update, provisioning_job: job,
                           result_snapshot: { "skipped" => true, "reason" => "pak_auth" })
      step = described_class.new(step_record: step_record, project: project, params: {})
      expect(step.already_completed?).to be(true)
    end
  end

  describe "#rollback" do
    context "when step was never applied (snapshot nil or updated false)" do
      let!(:auth_config) { create(:project_auth_config, :oidc, project: project) }

      it "does nothing when snapshot is nil" do
        step = build_step(result_snapshot: nil)
        expect { step.rollback }.not_to raise_error
        expect(a_request(:any, //)).not_to have_been_made
      end

      it "does nothing when snapshot has updated: false" do
        step = build_step(result_snapshot: { "updated" => false })
        expect { step.rollback }.not_to raise_error
        expect(a_request(:any, //)).not_to have_been_made
      end
    end

    context "when step was applied" do
      let!(:auth_config) do
        create(:project_auth_config, :oidc, project: project,
               redirect_uris: [ "https://new.example.com/cb" ],
               post_logout_redirect_uris: [ "https://new.example.com" ])
      end

      let(:uuid) { auth_config.keycloak_client_uuid }
      let(:previous_keycloak_state) do
        { "id" => uuid, "clientId" => auth_config.keycloak_client_id,
          "redirectUris" => [ "https://old.example.com/cb" ] }
      end
      let(:snapshot) do
        {
          "updated" => true,
          "keycloak_client_uuid" => uuid,
          "previous_state" => previous_keycloak_state,
          "previous_redirect_uris" => [ "https://old.example.com/cb" ],
          "previous_post_logout_redirect_uris" => [ "https://old.example.com" ]
        }
      end

      before { stub_keycloak_update_client(uuid: uuid) }

      it "reverts Keycloak to the previous state" do
        step = build_step(result_snapshot: snapshot)
        step.rollback
        expect(a_request(:put, /clients\/#{uuid}/)).to have_been_made
      end

      it "restores redirect_uris in project_auth_config" do
        step = build_step(result_snapshot: snapshot)
        step.rollback
        expect(auth_config.reload.redirect_uris).to eq([ "https://old.example.com/cb" ])
      end

      it "restores post_logout_redirect_uris in project_auth_config" do
        step = build_step(result_snapshot: snapshot)
        step.rollback
        expect(auth_config.reload.post_logout_redirect_uris).to eq([ "https://old.example.com" ])
      end

      it "does not raise when Keycloak returns 404 (client already gone)" do
        stub_request(:put, /clients\/#{uuid}/)
          .to_return(status: 404, body: { error: "not_found" }.to_json,
                     headers: { "Content-Type" => "application/json" })
        stub_keycloak_token
        step = build_step(result_snapshot: snapshot)
        expect { step.rollback }.not_to raise_error
      end

      it "still restores DB auth_config even when Keycloak returns 404" do
        stub_request(:put, /clients\/#{uuid}/)
          .to_return(status: 404, body: { error: "not_found" }.to_json,
                     headers: { "Content-Type" => "application/json" })
        stub_keycloak_token
        step = build_step(result_snapshot: snapshot)
        step.rollback
        config = auth_config.reload
        expect(config.redirect_uris).to eq([ "https://old.example.com/cb" ])
        expect(config.post_logout_redirect_uris).to eq([ "https://old.example.com" ])
      end
    end
  end
end
