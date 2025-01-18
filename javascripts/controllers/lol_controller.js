import { Controller } from "@hotwired/stimulus";
import "tocbot";

export default class extends Controller {

    static targets = [ "source", "expansion" ]

    connect() {
        console.debug("lol controller");
        const els = this.element.querySelectorAll("[data-expand]");
        els.forEach((el) => {
            el.onmouseenter = this.expand.bind(this);
        });
    }

    disconnect() {

    }


    expand(event) {
        console.debug("on click element", event);

        const target = event.srcElement.dataset.expand;
        this._expand(target);
    }

    clear(event) {
        console.debug("clear", event);
        this.expansionTarget.replaceChildren();
    }

    _expand(target) {
        const element = this.sourceTarget.querySelector(`#${target}`);
        if (element) {
            const clonedElement = element.cloneNode(true);
            clonedElement.classList.remove('hidden');
            let el = document.createElement("div");

            el.appendChild(clonedElement);
            this.expansionTarget.replaceChildren(el);
        }
        else {
            console.warn("node not found", target);
        }
    }


}
