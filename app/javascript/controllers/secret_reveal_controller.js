import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { storageKey: String }

  connect() {
    if (this.confirmed()) {
      this.scrubSecrets()
      this.element.hidden = true
    }
  }

  toggle(event) {
    const secret = event.params.secret || ""
    const field = this.secretField(event.params.targetId)
    if (!field) return

    const masked = field.dataset.masked !== "false"
    field.textContent = masked ? secret : this.secretMask(secret)
    field.dataset.masked = masked ? "false" : "true"
    event.currentTarget.textContent = masked ? "숨기기" : "표시"
  }

  async copy(event) {
    if (!navigator.clipboard) return

    const original = event.currentTarget.textContent

    try {
      await navigator.clipboard.writeText(event.params.secret || "")
      event.currentTarget.textContent = "복사됨"
      window.setTimeout(() => {
        event.currentTarget.textContent = original
      }, 1500)
    } catch (error) {
      event.currentTarget.textContent = "복사 실패"
      window.setTimeout(() => {
        event.currentTarget.textContent = original
      }, 1500)
    }
  }

  confirm() {
    this.setConfirmed()
    this.scrubSecrets()
    this.element.hidden = true
  }

  scrubSecrets() {
    this.element.querySelectorAll("[data-secret-reveal-secret-param]").forEach((button) => {
      delete button.dataset.secretRevealSecretParam
    })
    this.element.querySelectorAll("code[data-masked]").forEach((field) => {
      field.textContent = ""
      field.dataset.masked = "true"
    })
  }

  confirmed() {
    if (!this.hasStorageKeyValue || !window.sessionStorage) return false

    return window.sessionStorage.getItem(this.storageKeyValue) === "confirmed"
  }

  setConfirmed() {
    if (!this.hasStorageKeyValue || !window.sessionStorage) return

    window.sessionStorage.setItem(this.storageKeyValue, "confirmed")
  }

  secretField(id) {
    return this.element.querySelector(`#${id}`)
  }

  secretMask(value) {
    return "•".repeat(Math.max(16, value.length))
  }
}
