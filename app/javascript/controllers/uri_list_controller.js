import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template"]

  add() {
    if (!this.hasTemplateTarget) return

    const fragment = this.templateTarget.content.cloneNode(true)
    this.listTarget.append(fragment)
  }

  remove(event) {
    const row = event.currentTarget.closest(".uri-list__row")
    if (!row) return

    row.remove()
  }
}
