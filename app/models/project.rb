class Project < ApplicationRecord
  belongs_to :organization
  has_one :project_auth_config, dependent: :destroy
  has_many :project_api_keys, dependent: :destroy
  has_many :project_permissions, dependent: :destroy
  has_many :provisioning_jobs, dependent: :destroy
  has_many :config_versions, dependent: :destroy
  has_many :audit_logs, dependent: :nullify

  enum :status, {
    provisioning: 0,
    active: 1,
    update_pending: 2,
    deleting: 3,
    deleted: 4,
    provision_failed: 5
  }

  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :slug, presence: true, uniqueness: { scope: :organization_id }
  validates :app_id, presence: true, uniqueness: true

  before_validation :generate_app_id, on: :create, if: -> { app_id.blank? }
  before_validation :generate_slug, on: :create, if: -> { slug.blank? && name.present? }

  class AppIdGenerationError < StandardError; end

  APP_ID_MAX_ATTEMPTS = 10

  private

  def generate_app_id
    APP_ID_MAX_ATTEMPTS.times do
      candidate = "app-#{SecureRandom.alphanumeric(12)}"
      unless Project.exists?(app_id: candidate)
        self.app_id = candidate
        return
      end
    end
    raise AppIdGenerationError,
          "Could not generate a unique app_id after #{APP_ID_MAX_ATTEMPTS} attempts"
  end

  def generate_slug
    self.slug = name.downcase.gsub(/[^a-z0-9\s-]/, "").gsub(/\s+/, "-").gsub(/-+/, "-").strip.delete_prefix("-").delete_suffix("-")
  end
end
