module Projects
  class UpdateService
    # Fields that require external propagation via provisioning
    AUTH_CONFIG_FIELDS = %i[redirect_uris post_logout_redirect_uris].freeze
    LITELLM_CONFIG_FIELDS = %i[models guardrails s3_retention_days].freeze
    EXTERNAL_FIELDS = (AUTH_CONFIG_FIELDS + LITELLM_CONFIG_FIELDS).freeze

    def initialize(project:, params:, current_user_sub:)
      @project = project
      @params = params
      @current_user_sub = current_user_sub
    end

    def call
      return Result.failure("Cannot update a deleted project") if @project.deleted?

      dirty_external = compute_dirty_external_params
      dirty_metadata = compute_dirty_metadata_params
      needs_provisioning = dirty_external.any?

      # Short-circuit no-op submissions (e.g., user opened the unified edit
      # form, made no changes, hit save). Without this we'd write a
      # `project.update` audit log row with no useful changed_fields and,
      # for unified PATCH, surface success even though nothing happened.
      if dirty_external.empty? && dirty_metadata.empty?
        return Result.success({ project: @project, provisioning_job: nil })
      end

      if needs_provisioning
        return Result.failure("Another provisioning job is in progress") if active_job_exists?
      end

      provisioning_job = nil

      ActiveRecord::Base.transaction do
        @project.update!(dirty_metadata) if dirty_metadata.any?

        if needs_provisioning
          @project.update!(status: :update_pending)
          input_snapshot = dirty_external.deep_stringify_keys
          provisioning_job = @project.provisioning_jobs.create!(
            operation: "update",
            status: :pending,
            input_snapshot: input_snapshot
          )
          Provisioning::StepSeeder.call!(provisioning_job)
          ProvisioningExecuteJob.perform_later(
            provisioning_job.id,
            **dirty_external.merge(current_user_sub: @current_user_sub)
          )
        end

        AuditLog.create!(
          organization: @project.organization,
          project: @project,
          user_sub: @current_user_sub,
          action: "project.update",
          resource_type: "Project",
          resource_id: @project.id.to_s,
          details: { changed_fields: (dirty_metadata.keys + dirty_external.keys).map(&:to_s) }
        )
      end

      Result.success({ project: @project, provisioning_job: provisioning_job })
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.message)
    rescue ActiveRecord::RecordNotUnique
      Result.failure("Another provisioning job is in progress")
    end

    private

    # Compare submitted metadata to persisted state. The unified edit form
    # serializes a nil `description` as an empty string, so we normalize blanks
    # to nil before comparison; otherwise an unchanged form would mutate
    # description from nil to "" and write a misleading audit row.
    OPTIONAL_METADATA = %i[description].freeze

    def compute_dirty_metadata_params
      @params.slice(:name, :description).reject do |key, value|
        normalized_submitted = OPTIONAL_METADATA.include?(key) ? value.presence : value
        normalized_current = @project.public_send(key)
        normalized_current = normalized_current.presence if OPTIONAL_METADATA.include?(key)
        normalized_submitted == normalized_current
      end
    end

    def active_job_exists?
      @project.provisioning_jobs.where(status: ProvisioningJob::ACTIVE_STATUSES).exists?
    end

    # Compare each candidate external field against persisted state
    # (project_auth_config for auth, latest config_version snapshot for LiteLLM)
    # so a no-op submission of the unified edit form does not enqueue a
    # redundant provisioning job nor trip the active-job lock for a metadata-only edit.
    def compute_dirty_external_params
      dirty = {}
      EXTERNAL_FIELDS.each do |field|
        next unless @params.key?(field)
        submitted = @params[field]
        baseline = current_external_value(field)
        next if values_equivalent?(submitted, baseline)
        dirty[field] = submitted
      end
      dirty
    end

    def current_external_value(field)
      case field
      when :redirect_uris, :post_logout_redirect_uris
        Array(@project.project_auth_config&.public_send(field))
      when :models, :guardrails
        Array(latest_config_snapshot[field.to_s])
      when :s3_retention_days
        latest_config_snapshot["s3_retention_days"]
      end
    end

    def latest_config_snapshot
      @latest_config_snapshot ||= @project.config_versions.order(created_at: :desc).first&.snapshot || {}
    end

    def values_equivalent?(a, b)
      if a.is_a?(Array) || b.is_a?(Array)
        Array(a).map(&:to_s).sort == Array(b).map(&:to_s).sort
      else
        a.to_s == b.to_s
      end
    end
  end
end
