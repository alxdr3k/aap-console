import { Controller } from "@hotwired/stimulus"

const SECTION_LABEL = {
  meta: "메타데이터",
  auth: "인증 설정",
  litellm: "LiteLLM Config"
}

export default class extends Controller {
  static targets = ["form", "section", "badge", "summary", "summaryEmpty", "summaryList"]

  connect() {
    this.refresh()
  }

  track() {
    this.refresh()
  }

  refresh() {
    const dirtyFields = []

    this.sectionTargets.forEach((section) => {
      const sectionKey = section.dataset.section
      const fieldsInSection = section.querySelectorAll("[data-original-value]")
      let sectionDirty = false

      fieldsInSection.forEach((field) => {
        const original = field.dataset.originalValue
        const current = this.currentValue(field)
        if (current !== original) {
          sectionDirty = true
          const label = this.fieldLabel(field, sectionKey)
          if (label && !dirtyFields.includes(label)) dirtyFields.push(label)
        }
      })

      const badge = section.querySelector("[data-dirty-tracker-target='badge']")
      if (badge) badge.hidden = !sectionDirty
    })

    this.renderSummary(dirtyFields)
  }

  currentValue(field) {
    if (field.type === "checkbox") return field.checked.toString()
    return field.value
  }

  fieldLabel(field, _sectionKey) {
    if (field.type === "checkbox") {
      const fieldset = field.closest("fieldset")
      const legend = fieldset?.querySelector("legend")
      return legend ? legend.textContent.trim() : field.name
    }
    const label = field.closest(".field")?.querySelector("label")
    if (label) return label.textContent.trim()
    return field.name
  }

  renderSummary(dirtyFields) {
    if (!this.hasSummaryListTarget || !this.hasSummaryEmptyTarget) return

    while (this.summaryListTarget.firstChild) {
      this.summaryListTarget.removeChild(this.summaryListTarget.firstChild)
    }

    if (dirtyFields.length === 0) {
      this.summaryEmptyTarget.hidden = false
      this.summaryListTarget.hidden = true
      return
    }

    this.summaryEmptyTarget.hidden = true
    this.summaryListTarget.hidden = false
    dirtyFields.forEach((label) => {
      const li = document.createElement("li")
      li.textContent = label
      this.summaryListTarget.appendChild(li)
    })
  }
}
