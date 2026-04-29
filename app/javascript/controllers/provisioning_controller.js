import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

const TERMINAL_STATUSES = ["completed", "completed_with_warnings", "failed", "rolled_back", "rollback_failed"]

export default class extends Controller {
  static targets = ["status", "connection"]
  static values = {
    jobId: Number,
    pollUrl: String,
    stepUrlTemplate: String,
    pollInterval: { type: Number, default: 5000 }
  }

  connect() {
    this.polling = false
    this.startSubscription()
  }

  disconnect() {
    this.stopPolling()
    if (this.subscription) this.subscription.unsubscribe()
    if (this.consumer) this.consumer.disconnect()
  }

  startSubscription() {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "ProvisioningChannel", job_id: this.jobIdValue },
      {
        connected: () => this.useLiveConnection(),
        disconnected: () => this.usePollingFallback(),
        rejected: () => this.usePollingFallback(),
        received: (data) => this.receive(data)
      }
    )
  }

  receive(data) {
    if (data.type === "step_update" && data.step_id) {
      this.refreshStep(data.step_id)
    }

    if (data.type === "job_completed") {
      this.poll()
    }
  }

  startPolling() {
    if (this.pollTimer) return

    this.poll()
    this.pollTimer = window.setInterval(() => this.poll(), this.pollIntervalValue)
  }

  stopPolling() {
    if (!this.pollTimer) return

    window.clearInterval(this.pollTimer)
    this.pollTimer = null
  }

  async poll() {
    if (this.polling) return

    this.polling = true
    try {
      const response = await fetch(this.pollUrlValue, { headers: { Accept: "application/json" } })
      if (!response.ok) return

      const payload = await response.json()
      this.updateJobStatus(payload.status)
      await Promise.all((payload.steps || []).map((step) => this.refreshStep(step.id)))

      if (TERMINAL_STATUSES.includes(payload.status)) this.stopPolling()
    } finally {
      this.polling = false
    }
  }

  async refreshStep(stepId) {
    const current = this.element.querySelector(`[data-step-id="${stepId}"]`)
    if (!current) return

    const url = this.stepUrlTemplateValue.replace("__STEP_ID__", stepId)
    const response = await fetch(url, { headers: { Accept: "text/html" } })
    if (!response.ok) return

    current.outerHTML = await response.text()
  }

  updateJobStatus(status) {
    if (!this.hasStatusTarget || !status) return

    this.statusTarget.textContent = status
    this.statusTarget.className = this.jobStatusClass(status)
  }

  updateConnection(label) {
    if (!this.hasConnectionTarget) return

    this.connectionTarget.textContent = label
  }

  useLiveConnection() {
    this.stopPolling()
    this.updateConnection("live")
  }

  usePollingFallback() {
    this.updateConnection("polling")
    this.startPolling()
  }

  jobStatusClass(status) {
    if (["completed", "completed_with_warnings"].includes(status)) return "badge"
    if (["failed", "rollback_failed"].includes(status)) return "badge badge--danger"
    if (status === "rolled_back") return "badge badge--muted"

    return "badge badge--warning"
  }
}
