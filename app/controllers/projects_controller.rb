class ProjectsController < ApplicationController
  AVAILABLE_MODELS = %w[azure-gpt4 claude-sonnet gemini-pro].freeze
  AVAILABLE_GUARDRAILS = %w[content-filter token-limit].freeze
  DEFAULT_S3_RETENTION_DAYS = 90
  ENABLED_AUTH_TYPES = %w[oidc oauth].freeze

  before_action :set_organization
  before_action -> { authorize_org!(@organization) }, only: [ :index ]
  before_action -> { authorize_org!(@organization, minimum_role: :admin) }, only: [ :new, :create, :destroy ]
  before_action :set_project, only: [ :show, :update, :destroy ]
  before_action -> { authorize_project!(@project) }, only: [ :show ]
  before_action -> { authorize_project!(@project, minimum_role: :write) }, only: [ :update ]

  def index
    @projects = current_authorization.accessible_projects(@organization)
                                     .includes(:provisioning_jobs)
                                     .order(:name)

    return render json: @projects if default_json_request?

    respond_to do |format|
      format.html
      format.json { render json: @projects }
    end
  end

  def new
    @project = @organization.projects.new
    prepare_project_form

    respond_to do |format|
      format.html
      format.json { render json: {} }
    end
  end

  def create
    attributes = normalized_project_params
    form_errors = project_form_errors(attributes)

    if form_errors.any?
      if html_project_request?
        @project = @organization.projects.new(attributes.slice(:name, :description))
        @errors = form_errors
        prepare_project_form(attributes)
        return render :new, status: :unprocessable_entity
      else
        return render json: { errors: form_errors }, status: :unprocessable_entity
      end
    end

    result = Projects::CreateService.new(
      organization: @organization,
      params: attributes,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      project = result.data
      provisioning_job = project.provisioning_jobs.last
      flash[:success] = "Project 생성 프로비저닝을 시작했습니다."
      redirect_to provisioning_job_path(provisioning_job), status: :see_other
    else
      @project = @organization.projects.new(attributes.slice(:name, :description))
      @errors = [ result.error ]
      prepare_project_form(attributes)

      return render json: { errors: @errors }, status: :unprocessable_entity if default_json_request?

      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @errors }, status: :unprocessable_entity }
      end
    end
  end

  def show
    prepare_project_show

    return render json: @project if default_json_request?

    respond_to do |format|
      format.html
      format.json { render json: @project }
    end
  end

  def update
    result = Projects::UpdateService.new(
      project: @project,
      params: project_update_params.to_h.symbolize_keys,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      return render json: @project if default_json_request?

      respond_to do |format|
        format.html do
          flash[:success] = "Project 정보가 저장되었습니다."
          redirect_to organization_project_path(@organization.slug, @project.slug), status: :see_other
        end
        format.json { render json: @project }
      end
    else
      @errors = [ result.error ]
      prepare_project_show

      return render json: { errors: @errors }, status: :unprocessable_entity if default_json_request?

      respond_to do |format|
        format.html { render :show, status: :unprocessable_entity }
        format.json { render json: { errors: @errors }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    result = Projects::DestroyService.new(
      project: @project,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      project = result.data
      provisioning_job = project.provisioning_jobs.where(operation: "delete").last
      flash[:success] = "Project 삭제 프로비저닝을 시작했습니다."
      redirect_to provisioning_job_path(provisioning_job), status: :see_other
    else
      @errors = [ result.error ]
      prepare_project_show

      return render json: { errors: @errors }, status: :unprocessable_entity if default_json_request?

      respond_to do |format|
        format.html { render :show, status: :unprocessable_entity }
        format.json { render json: { errors: @errors }, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_organization
    @organization = Organization.find_by!(slug: params[:organization_slug])
  rescue ActiveRecord::RecordNotFound
    return render json: { error: "Not found" }, status: :not_found if default_json_request?

    respond_to do |format|
      format.html { render "organizations/not_found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def set_project
    @project = @organization.projects.find_by!(slug: params[:slug])
  rescue ActiveRecord::RecordNotFound
    return render json: { error: "Not found" }, status: :not_found if default_json_request?

    respond_to do |format|
      format.html { render :not_found, status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def prepare_project_form(attributes = {})
    @available_models = AVAILABLE_MODELS
    @available_guardrails = AVAILABLE_GUARDRAILS
    @selected_models = Array(attributes[:models]).compact_blank
    @selected_guardrails = Array(attributes[:guardrails]).compact_blank
    @selected_auth_type = attributes[:auth_type].presence || "oidc"
    @s3_retention_days = attributes[:s3_retention_days].presence || DEFAULT_S3_RETENTION_DAYS
  end

  def prepare_project_show
    @auth_config = @project.project_auth_config
    @active_provisioning_job = @project.provisioning_jobs
                                      .where(status: ProvisioningJob::ACTIVE_STATUSES)
                                      .order(created_at: :desc)
                                      .first
    @latest_provisioning_job = @project.provisioning_jobs.order(created_at: :desc).first
    @provisioning_jobs = @project.provisioning_jobs.order(created_at: :desc).limit(5)
    @config_versions = @project.config_versions.order(created_at: :desc).limit(3)
    @latest_config_version = @config_versions.first
    @latest_config_snapshot = latest_config_snapshot
  end

  def latest_config_snapshot
    @latest_config_version&.snapshot.presence || @latest_provisioning_job&.input_snapshot.presence || {}
  end

  def normalized_project_params
    attrs = project_params.to_h.symbolize_keys
    attrs[:models] = Array(attrs[:models]).compact_blank
    attrs[:guardrails] = Array(attrs[:guardrails]).compact_blank
    attrs[:s3_retention_days] = attrs[:s3_retention_days].presence || DEFAULT_S3_RETENTION_DAYS
    attrs
  end

  def project_form_errors(attributes)
    errors = []
    errors << "허용되지 않은 인증 방식입니다. OIDC 또는 OAuth를 선택하세요." unless ENABLED_AUTH_TYPES.include?(attributes[:auth_type].to_s)

    submitted_models = Array(attributes[:models]).compact_blank
    errors << "모델을 하나 이상 선택하세요." if submitted_models.blank?
    unknown_models = submitted_models - AVAILABLE_MODELS
    errors << "허용되지 않은 모델: #{unknown_models.join(', ')}" if unknown_models.any?

    submitted_guardrails = Array(attributes[:guardrails]).compact_blank
    unknown_guardrails = submitted_guardrails - AVAILABLE_GUARDRAILS
    errors << "허용되지 않은 가드레일: #{unknown_guardrails.join(', ')}" if unknown_guardrails.any?

    retention_days = attributes[:s3_retention_days].to_i
    unless retention_days.between?(1, 3650)
      errors << "S3 Retention은 1일부터 3650일 사이여야 합니다."
    end

    errors
  end

  def html_project_request?
    request.format.html? && !default_json_request?
  end

  def project_params
    params.require(:project).permit(:name, :description, :auth_type, :s3_retention_days, models: [], guardrails: [])
  end

  def project_update_params
    params.require(:project).permit(:name, :description)
  end
end
