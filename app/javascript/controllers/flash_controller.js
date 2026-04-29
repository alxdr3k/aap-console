import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { timeout: Number }

  connect() {
    if (this.timeoutValue > 0) {
      this.timer = window.setTimeout(() => this.close(), this.timeoutValue)
    }
  }

  disconnect() {
    window.clearTimeout(this.timer)
  }

  close() {
    this.element.remove()
  }
}
