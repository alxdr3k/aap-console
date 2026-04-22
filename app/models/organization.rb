class Organization < ApplicationRecord
  has_many :projects, dependent: :destroy
  has_many :org_memberships, dependent: :destroy
  has_many :audit_logs, dependent: :nullify

  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug, on: :create, if: -> { slug.blank? && name.present? }

  private

  def generate_slug
    self.slug = name.downcase.gsub(/[^a-z0-9\s-]/, "").gsub(/\s+/, "-").gsub(/-+/, "-").strip.delete_prefix("-").delete_suffix("-")
  end
end
