import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["list"];
  static values = {
    apiUrl: String
  };

  connect() {
    this.bookmarks = [];
    this.fetchBookmarks();
  }

  async fetchBookmarks() {
    try {
      const response = await fetch(this.apiUrlValue);
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);

      const r = await response.json();
      this.bookmarks = r['bookmarks'];

      this.render();
    } catch (error) {
      this.listTarget.innerHTML = `<li>Error loading bookmarks: ${error.message}</li>`;
      this.prevBtnTarget.disabled = true;
      this.nextBtnTarget.disabled = true;
    }
  }

  render() {
    const paginated = this.bookmarks;

    if (paginated.length === 0) {
      this.listTarget.innerHTML = "<li>No bookmarks found.</li>";
    } else {
      this.listTarget.innerHTML = paginated.map(bm => `<li>${this.renderBookmark(bm)}</li>`).join("");
    }
  }

  renderBookmark(bookmark) {
    const tags = bookmark.tags || [];
    bookmark = bookmark.content;  // do this first
    const title = bookmark.title || "Untitled";
    const description = bookmark.description;
    const url = bookmark.url || "#";

    const tagsHtml = tags.map(t => `<span class='text-xs tag'>${t.name}</span>`).join(" ");

    return `<a href="${url}" target="_blank" rel="noopener noreferrer">
            <div>${title}</div>
            <div class="text-sm text-gray-400">${description}</div>
            <div>${tagsHtml}</div>
          </a>`;
  }

}
