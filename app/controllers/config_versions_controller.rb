class ConfigVersionsController < ApplicationController
  before_action :set_project_context, only: [ :index ]
  before_action -> { authorize_project!(@project) }, only: [ :index ]
  before_action :set_config_version, only: [ :show, :rollback ]
  before_action :authorize_config_version_read!, only: [ :show ]
  before_action :authorize_config_version_write!, only: [ :rollback ]

  def index
    @config_versions = ordered_project_versions
    prepare_index_state

    return render json: @config_versions if json_request?

    respond_to do |format|
      format.html
      format.json { render json: @config_versions }
    end
  end

  def show
    return render json: @config_version if json_request?

    prepare_detail_state(@config_version)

    respond_to do |format|
      format.html
      format.json { render json: @config_version }
    end
  end

  def rollback
    result = ConfigVersions::RollbackService.new(
      config_version: @config_version,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      return render json: rollback_payload(result.data), status: :ok if json_request?

      flash[:success] = "Config #{result.data.rollback_version.version_id} 버전으로 롤백되었습니다."
      flash[:rollback_result] = rollback_flash_payload(result.data)
      redirect_to organization_project_config_versions_path(
        @config_version.project.organization.slug,
        @config_version.project.slug,
        version_id: result.data.rollback_version.id
      ), status: :see_other
    else
      return render json: rollback_error_payload(result.error), status: result.error.fetch(:status) if json_request?

      flash[:error] = result.error.fetch(:message)
      flash[:rollback_result] = rollback_error_flash_payload(result.error)
      redirect_to organization_project_config_versions_path(
        @config_version.project.organization.slug,
        @config_version.project.slug,
        version_id: @config_version.id
      ), status: :see_other
    end
  end

  private

  def set_project_context
    @organization = Organization.find_by!(slug: params[:organization_slug])
    @project = @organization.projects.find_by!(slug: params[:project_slug])
  rescue ActiveRecord::RecordNotFound
    return render json: { error: "Not found" }, status: :not_found if json_request?

    respond_to do |format|
      format.html { render "projects/not_found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def set_config_version
    @config_version = ConfigVersion.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    return render json: { error: "Not found" }, status: :not_found if json_request?

    respond_to do |format|
      format.html { render "projects/not_found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def authorize_config_version_read!
    return if @config_version.nil?
    authorize_project!(@config_version.project)
  end

  def authorize_config_version_write!
    return if @config_version.nil?
    authorize_project!(@config_version.project, minimum_role: :write)
  end

  def rollback_payload(data)
    {
      status: "completed",
      target_version_id: @config_version.version_id,
      config_version: data.rollback_version,
      diagnostics: data.diagnostics
    }
  end

  def rollback_error_payload(error)
    {
      status: error.fetch(:response_status),
      error: error.fetch(:message),
      target_version_id: @config_version.version_id,
      diagnostics: error.fetch(:diagnostics)
    }
  end

  def ordered_project_versions
    @ordered_project_versions ||= @project.config_versions.order(created_at: :desc).to_a
  end

  def prepare_index_state
    @can_write_project = current_authorization.can?(:write_project, @project)
    @active_provisioning_job = active_provisioning_job_for(@project)
    @rollback_result = flash[:rollback_result]

    selected_version = selected_project_version
    return unless selected_version

    @selected_config_version = selected_version
    @selected_comparison_version = comparison_version_for(selected_version, ordered_project_versions)
    @selected_diff_lines = diff_lines_for(selected_version, @selected_comparison_version)
  end

  def prepare_detail_state(config_version)
    @organization = config_version.project.organization
    @project = config_version.project
    @can_write_project = current_authorization.can?(:write_project, @project)
    @active_provisioning_job = active_provisioning_job_for(@project)
    @comparison_config_version = comparison_version_for(config_version, ordered_versions_for(config_version.project))
    @diff_lines = diff_lines_for(config_version, @comparison_config_version)
  end

  def ordered_versions_for(project)
    project.config_versions.order(created_at: :desc).to_a
  end

  def selected_project_version
    return ordered_project_versions.first if params[:version_id].blank?

    ordered_project_versions.find { |version| version.id == params[:version_id].to_i } || ordered_project_versions.first
  end

  def comparison_version_for(config_version, versions)
    current_index = versions.index(config_version)
    current_index ? versions[current_index + 1] : nil
  end

  def diff_lines_for(config_version, comparison_version)
    ConfigVersions::DiffBuilder.new(
      before_snapshot: comparison_version&.snapshot,
      after_snapshot: config_version.snapshot,
      before_label: comparison_version&.version_id || "empty",
      after_label: config_version.version_id
    ).lines
  end

  def active_provisioning_job_for(project)
    project.provisioning_jobs.where(status: ProvisioningJob::ACTIVE_STATUSES).order(created_at: :desc).first
  end

  def rollback_flash_payload(data)
    {
      "status" => "completed",
      "target_version_id" => @config_version.version_id,
      "rollback_version_id" => data.rollback_version.version_id,
      "diagnostics" => data.diagnostics
    }
  end

  def rollback_error_flash_payload(error)
    {
      "status" => error.fetch(:response_status),
      "error" => error.fetch(:message),
      "target_version_id" => @config_version.version_id,
      "diagnostics" => error.fetch(:diagnostics)
    }
  end

  def json_request?
    request.format.json? || default_json_request?
  end
end
