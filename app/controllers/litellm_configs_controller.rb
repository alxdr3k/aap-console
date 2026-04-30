class LitellmConfigsController < ApplicationController
  AVAILABLE_MODELS = ProjectsController::AVAILABLE_MODELS
  AVAILABLE_GUARDRAILS = ProjectsController::AVAILABLE_GUARDRAILS
  DEFAULT_S3_RETENTION_DAYS = ProjectsController::DEFAULT_S3_RETENTION_DAYS

  before_action :set_organization
  before_action :set_project
  before_action -> { authorize_project!(@project) }, only: [ :show ]
  before_action -> { authorize_project!(@project, minimum_role: :write) }, only: [ :update ]

  def show
    return render json: latest_config_snapshot if json_request?

    prepare_show

    respond_to do |format|
      format.html
      format.json { render json: latest_config_snapshot }
    end
  end

  # LiteLLM config mutations are routed through Projects::UpdateService and
  # propagate via a provisioning job. The response mirrors AuthConfigsController#update:
  # 202 Accepted + provisioning_job_id when a job is enqueued, 200 OK when no
  # external state needs to change. See docs/02_HLD.md §5.6.
  def update
    validation_errors = litellm_config_errors(litellm_config_params)
    if validation_errors.any?
      return render json: { errors: validation_errors }, status: :unprocessable_entity if json_request?

      @errors = validation_errors
      prepare_show(form_values: litellm_config_params)
      return render :show, status: :unprocessable_entity
    end

    result = Projects::UpdateService.new(
      project: @project,
      params: litellm_config_params,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      provisioning_job = result.data[:provisioning_job]

      if json_request?
        if provisioning_job
          render json: { provisioning_job_id: provisioning_job.id }, status: :accepted
        else
          render json: { message: "Config updated" }, status: :ok
        end
      elsif provisioning_job
        flash[:success] = "LiteLLM 설정 변경 프로비저닝을 시작했습니다."
        redirect_to provisioning_job_path(provisioning_job), status: :see_other
      else
        flash[:success] = "LiteLLM 설정이 저장되었습니다."
        redirect_to organization_project_litellm_config_path(@organization.slug, @project.slug), status: :see_other
      end
    else
      return render json: { errors: [ result.error ] }, status: :unprocessable_entity if json_request?

      @errors = [ result.error ]
      prepare_show(form_values: litellm_config_params)
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_organization
    @organization = Organization.find_by!(slug: params[:organization_slug])
  rescue ActiveRecord::RecordNotFound
    return render json: { error: "Not found" }, status: :not_found if json_request?

    respond_to do |format|
      format.html { render "projects/not_found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def set_project
    @project = @organization.projects.find_by!(slug: params[:project_slug])
  rescue ActiveRecord::RecordNotFound
    return render json: { error: "Not found" }, status: :not_found if json_request?

    respond_to do |format|
      format.html { render "projects/not_found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def litellm_config_params
    permitted = params.require(:litellm_config).permit(:s3_retention_days, models: [], guardrails: [])
    normalized = {}
    normalized[:models] = normalize_list(permitted[:models]) if permitted.key?(:models)
    normalized[:guardrails] = normalize_list(permitted[:guardrails]) if permitted.key?(:guardrails)
    if permitted.key?(:s3_retention_days)
      normalized[:s3_retention_days] = permitted[:s3_retention_days].presence&.to_i
    end
    normalized
  end

  def latest_config_snapshot
    @latest_config_snapshot ||= @project.config_versions.order(created_at: :desc).first&.snapshot || {}
  end

  def prepare_show(form_values: nil)
    base_values = latest_config_snapshot.deep_symbolize_keys
    values = base_values.merge(form_values || {})

    @errors ||= []
    @can_write_project = current_authorization.can?(:write_project, @project)
    @active_provisioning_job = @project.provisioning_jobs
                                      .where(status: ProvisioningJob::ACTIVE_STATUSES)
                                      .order(created_at: :desc)
                                      .first
    @available_models = AVAILABLE_MODELS
    @available_guardrails = AVAILABLE_GUARDRAILS
    @selected_models = Array(values[:models]).compact_blank
    @selected_guardrails = Array(values[:guardrails]).compact_blank
    @s3_retention_days = values[:s3_retention_days].presence || DEFAULT_S3_RETENTION_DAYS
    @s3_path = values[:s3_path].presence || "#{@organization.slug}/#{@project.slug}/"
    @latest_config_version = @project.config_versions.order(created_at: :desc).first
  end

  def litellm_config_errors(config)
    errors = []
    errors << "모델을 하나 이상 선택하세요." if config.key?(:models) && config[:models].blank?

    if config.key?(:s3_retention_days)
      retention_days = config[:s3_retention_days].to_i
      unless retention_days.between?(1, 3650)
        errors << "S3 Retention은 1일부터 3650일 사이여야 합니다."
      end
    end

    errors
  end

  def normalize_list(values)
    Array(values).map(&:to_s).map(&:strip).reject(&:blank?)
  end

  def json_request?
    request.format.json? || default_json_request?
  end
end
