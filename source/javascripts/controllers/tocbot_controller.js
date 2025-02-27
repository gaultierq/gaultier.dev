import { Controller } from "@hotwired/stimulus";
import "tocbot";

export default class extends Controller {
    connect() {
        window.tocbot.init({
            // Where to render the table of contents.
            tocSelector: '.js-toc',
            // Where to grab the headings to build the table of contents.
            contentSelectorElement: this.element,
            // Which headings to grab inside of the contentSelector element.
            headingSelector: 'h1, h2, h3',
            // For headings inside relative or absolute positioned containers within content.
            hasInnerContainers: false,
            scrollSmooth: false,
        });

    }
}
