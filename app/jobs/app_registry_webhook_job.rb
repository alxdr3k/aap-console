class AppRegistryWebhookJob < ApplicationJob
  queue_as :webhooks

  retry_on BaseClient::ApiError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(app_id:, action:, app_data: {})
    client = ConfigServerClient.new
    client.notify_app_registry(
      action: action,
      app_data: app_data,
      idempotency_key: "app-registry-#{action}-#{app_id}"
    )
  end
end
