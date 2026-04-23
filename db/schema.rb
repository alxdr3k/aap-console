# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_22_005216) do
  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.json "details"
    t.integer "organization_id"
    t.integer "project_id"
    t.string "resource_id"
    t.string "resource_type", null: false
    t.datetime "updated_at", null: false
    t.string "user_sub", null: false
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["organization_id", "created_at"], name: "index_audit_logs_on_organization_id_and_created_at"
    t.index ["project_id", "created_at"], name: "index_audit_logs_on_project_id_and_created_at"
  end

  create_table "config_versions", force: :cascade do |t|
    t.text "change_summary"
    t.string "change_type", null: false
    t.string "changed_by_sub", null: false
    t.datetime "created_at", null: false
    t.integer "project_id", null: false
    t.integer "provisioning_job_id"
    t.json "snapshot"
    t.datetime "updated_at", null: false
    t.string "version_id", null: false
    t.index ["project_id", "created_at"], name: "index_config_versions_on_project_id_and_created_at"
    t.index ["project_id"], name: "index_config_versions_on_project_id"
    t.index ["provisioning_job_id"], name: "index_config_versions_on_provisioning_job_id"
  end

  create_table "org_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "invited_at"
    t.datetime "joined_at"
    t.integer "organization_id", null: false
    t.string "role", default: "read", null: false
    t.datetime "updated_at", null: false
    t.string "user_sub", null: false
    t.index ["organization_id", "user_sub"], name: "index_org_memberships_on_organization_id_and_user_sub", unique: true
    t.index ["organization_id"], name: "index_org_memberships_on_organization_id"
    t.index ["user_sub"], name: "index_org_memberships_on_user_sub"
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "langfuse_org_id"
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
  end

  create_table "project_api_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.integer "project_id", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "name"], name: "index_project_api_keys_on_project_id_and_name", unique: true
    t.index ["project_id"], name: "index_project_api_keys_on_project_id"
    t.index ["token_digest"], name: "index_project_api_keys_on_token_digest", unique: true
  end

  create_table "project_auth_configs", force: :cascade do |t|
    t.string "auth_type", null: false
    t.datetime "created_at", null: false
    t.string "keycloak_client_id"
    t.string "keycloak_client_uuid"
    t.json "post_logout_redirect_uris"
    t.integer "project_id", null: false
    t.json "redirect_uris"
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_project_auth_configs_on_project_id", unique: true
  end

  create_table "project_permissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "org_membership_id", null: false
    t.integer "project_id", null: false
    t.string "role", default: "read", null: false
    t.datetime "updated_at", null: false
    t.index ["org_membership_id", "project_id"], name: "index_project_permissions_on_org_membership_id_and_project_id", unique: true
    t.index ["project_id"], name: "index_project_permissions_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "app_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "organization_id", null: false
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["app_id"], name: "index_projects_on_app_id", unique: true
    t.index ["organization_id", "slug"], name: "index_projects_on_organization_id_and_slug", unique: true
    t.index ["organization_id", "status"], name: "index_projects_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_projects_on_organization_id"
  end

  create_table "provisioning_jobs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "operation", null: false
    t.integer "project_id", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.json "warnings"
    t.index ["project_id", "status"], name: "index_provisioning_jobs_on_project_id_and_status"
    t.index ["project_id"], name: "idx_active_provisioning_job_per_project", unique: true, where: "status IN (0, 1, 5, 6)"
    t.index ["project_id"], name: "index_provisioning_jobs_on_project_id"
    t.index ["status"], name: "index_provisioning_jobs_on_status"
  end

  create_table "provisioning_steps", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "max_retries", default: 3
    t.string "name", null: false
    t.integer "provisioning_job_id", null: false
    t.json "result_snapshot"
    t.integer "retry_count", default: 0
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.integer "step_order", null: false
    t.datetime "updated_at", null: false
    t.index ["provisioning_job_id", "name"], name: "index_provisioning_steps_on_job_id_and_name", unique: true
    t.index ["provisioning_job_id", "step_order"], name: "index_provisioning_steps_on_provisioning_job_id_and_step_order"
    t.index ["provisioning_job_id"], name: "index_provisioning_steps_on_provisioning_job_id"
  end

  add_foreign_key "audit_logs", "organizations"
  add_foreign_key "audit_logs", "projects"
  add_foreign_key "config_versions", "projects"
  add_foreign_key "config_versions", "provisioning_jobs"
  add_foreign_key "org_memberships", "organizations"
  add_foreign_key "project_api_keys", "projects"
  add_foreign_key "project_auth_configs", "projects"
  add_foreign_key "project_permissions", "org_memberships"
  add_foreign_key "project_permissions", "projects"
  add_foreign_key "projects", "organizations"
  add_foreign_key "provisioning_jobs", "projects"
  add_foreign_key "provisioning_steps", "provisioning_jobs"
end
