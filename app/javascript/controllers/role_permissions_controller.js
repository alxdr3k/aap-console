import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["role", "permissions"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasPermissionsTarget) return

    this.permissionsTarget.hidden = this.roleTarget.value === "admin"
  }
}
