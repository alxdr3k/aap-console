import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["role", "permissions"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasPermissionsTarget) return

    const admin = this.roleTarget.value === "admin"
    this.permissionsTarget.hidden = admin

    this.permissionsTarget.querySelectorAll("input, select, textarea").forEach((field) => {
      if (admin) this.clearField(field)
      field.disabled = admin
    })
  }

  clearField(field) {
    if (field.type === "checkbox" || field.type === "radio") {
      field.checked = false
    } else if (field.tagName === "SELECT") {
      field.value = field.querySelector("option[value='read']") ? "read" : field.options[0]?.value
    } else {
      field.value = ""
    }
  }
}
