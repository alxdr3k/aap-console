import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

const TERMINAL_STATUSES = ["completed", "completed_with_warnings", "failed", "rolled_back", "rollback_failed"]
const SECRET_REVEAL_STATUSES = ["completed", "completed_with_warnings"]

export default class extends Controller {
  static targets = ["status", "connection", "secrets", "secretList", "targetLink"]
  static values = {
    jobId: Number,
    pollUrl: String,
    secretsUrl: String,
    status: String,
    stepUrlTemplate: String,
    pollInterval: { type: Number, default: 5000 }
  }

  connect() {
    this.disconnecting = false
    this.polling = false
    this.loadingSecrets = false
    this.stepSnapshots = this.readStepSnapshots()
    this.startSubscription()
    this.updateJobStatus(this.statusValue)
  }

  disconnect() {
    this.disconnecting = true
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
      const changedSteps = (payload.steps || []).filter((step) => this.stepChanged(step))
      await Promise.all(changedSteps.map((step) => this.refreshStep(step.id)))

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
    this.updateStepSnapshotFromElement(stepId)
  }

  updateJobStatus(status) {
    if (!status) return

    this.statusValue = status
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = status
      this.statusTarget.className = this.jobStatusClass(status)
    }

    if (SECRET_REVEAL_STATUSES.includes(status)) this.loadSecrets()
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
    if (this.disconnecting) return

    this.updateConnection("polling")
    this.startPolling()
  }

  readStepSnapshots() {
    const snapshots = new Map()
    this.element.querySelectorAll("[data-step-id]").forEach((stepElement) => {
      snapshots.set(stepElement.dataset.stepId, stepElement.dataset.stepSnapshot || "")
    })

    return snapshots
  }

  stepChanged(step) {
    return this.stepSnapshots.get(String(step.id)) !== this.stepSnapshot(step)
  }

  stepSnapshot(step) {
    return JSON.stringify([step.status, step.error_message || "", step.retry_count || 0])
  }

  updateStepSnapshotFromElement(stepId) {
    const stepElement = this.element.querySelector(`[data-step-id="${stepId}"]`)
    if (!stepElement) return

    this.stepSnapshots.set(String(stepId), stepElement.dataset.stepSnapshot || "")
  }

  async loadSecrets() {
    if (!this.hasSecretsTarget || !this.hasSecretListTarget || !this.hasSecretsUrlValue) return
    if (this.loadingSecrets || this.secretsConfirmed()) return

    this.loadingSecrets = true
    try {
      const response = await fetch(this.secretsUrlValue, { headers: { Accept: "application/json" } })
      if (!response.ok) return

      const entries = this.secretEntries(await response.json())
      if (entries.length === 0) return

      this.renderSecrets(entries)
      this.lockTargetLink()
      this.secretsTarget.hidden = false
    } finally {
      this.loadingSecrets = false
    }
  }

  secretEntries(payload) {
    return Object.entries(payload.secrets || {}).map(([key, secret]) => ({
      key,
      label: secret.label || key,
      value: secret.value || ""
    })).filter((secret) => secret.value.length > 0)
  }

  renderSecrets(entries) {
    this.secretListTarget.replaceChildren(...entries.map((secret) => this.secretRow(secret)))
  }

  secretRow(secret) {
    const row = document.createElement("div")
    const label = document.createElement("dt")
    const value = document.createElement("dd")
    const secretValue = document.createElement("code")
    const showButton = document.createElement("button")
    const copyButton = document.createElement("button")

    label.textContent = secret.label
    secretValue.textContent = this.secretMask(secret.value)
    secretValue.dataset.masked = "true"

    showButton.type = "button"
    showButton.className = "button button--secondary"
    showButton.textContent = "표시"
    showButton.addEventListener("click", () => this.toggleSecret(secretValue, showButton, secret.value))

    copyButton.type = "button"
    copyButton.className = "button button--secondary"
    copyButton.textContent = "복사"
    copyButton.addEventListener("click", () => this.copySecret(secret.value, copyButton))

    value.append(secretValue, showButton, copyButton)
    row.append(label, value)
    return row
  }

  toggleSecret(secretValue, button, value) {
    const masked = secretValue.dataset.masked === "true"
    secretValue.textContent = masked ? value : this.secretMask(value)
    secretValue.dataset.masked = masked ? "false" : "true"
    button.textContent = masked ? "숨김" : "표시"
  }

  async copySecret(value, button) {
    if (!navigator.clipboard) return

    try {
      await navigator.clipboard.writeText(value)
      button.textContent = "복사됨"
    } catch {
      button.textContent = "복사 실패"
    }
  }

  confirmSecrets() {
    try {
      window.localStorage.setItem(this.secretConfirmationKey(), "true")
    } catch {
      // Local storage can be disabled; confirmation still applies to this page.
    }

    if (this.hasSecretsTarget) this.secretsTarget.hidden = true
    this.unlockTargetLink()
  }

  secretsConfirmed() {
    try {
      return window.localStorage.getItem(this.secretConfirmationKey()) === "true"
    } catch {
      return false
    }
  }

  secretConfirmationKey() {
    return `provisioning:${this.jobIdValue}:secrets-confirmed`
  }

  secretMask(value) {
    return "*".repeat(Math.min(Math.max(value.length, 8), 24))
  }

  lockTargetLink() {
    if (!this.hasTargetLinkTarget || this.targetLinkTarget.dataset.originalHref) return

    this.targetLinkTarget.dataset.originalHref = this.targetLinkTarget.getAttribute("href") || ""
    this.targetLinkTarget.removeAttribute("href")
    this.targetLinkTarget.classList.add("button--disabled")
    this.targetLinkTarget.setAttribute("aria-disabled", "true")
  }

  unlockTargetLink() {
    if (!this.hasTargetLinkTarget || !this.targetLinkTarget.dataset.originalHref) return

    this.targetLinkTarget.setAttribute("href", this.targetLinkTarget.dataset.originalHref)
    this.targetLinkTarget.classList.remove("button--disabled")
    this.targetLinkTarget.removeAttribute("aria-disabled")
    delete this.targetLinkTarget.dataset.originalHref
  }

  jobStatusClass(status) {
    if (["completed", "completed_with_warnings"].includes(status)) return "badge"
    if (["failed", "rollback_failed"].includes(status)) return "badge badge--danger"
    if (status === "rolled_back") return "badge badge--muted"

    return "badge badge--warning"
  }
}
