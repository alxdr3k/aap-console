import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "results", "userSub"]
  static values = { url: String }

  connect() {
    this.timer = null
  }

  search() {
    clearTimeout(this.timer)
    this.userSubTarget.value = ""

    const query = this.queryTarget.value.trim()
    if (query.length < 2) {
      this.resultsTarget.replaceChildren()
      return
    }

    this.timer = setTimeout(() => this.fetchUsers(query), 180)
  }

  select(event) {
    event.preventDefault()

    const button = event.currentTarget
    this.userSubTarget.value = button.dataset.userSub
    this.queryTarget.value = button.dataset.label
    this.resultsTarget.replaceChildren()
  }

  clearSelection() {
    this.userSubTarget.value = ""
    this.queryTarget.value = ""
    this.resultsTarget.replaceChildren()
  }

  fetchUsers(query) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", query)

    fetch(url, { headers: { Accept: "application/json" } })
      .then((response) => (response.ok ? response.json() : { users: [] }))
      .then((payload) => this.renderResults(payload.users || []))
  }

  renderResults(users) {
    this.resultsTarget.replaceChildren(...users.slice(0, 6).map((user) => this.resultButton(user)))
  }

  resultButton(user) {
    const button = document.createElement("button")
    const email = user.email || user.username || user.id
    const name = [user.firstName, user.lastName].filter(Boolean).join(" ")
    button.type = "button"
    button.className = "autocomplete-result"
    button.dataset.action = "user-search#select"
    button.dataset.userSub = user.id
    button.dataset.label = name ? `${email} - ${name}` : email
    button.textContent = button.dataset.label
    return button
  }
}
