import { Application } from "@hotwired/stimulus";
import TocbotController from "./controllers/tocbot_controller.js";
import HighlightContoller from "./controllers/highlightjs_controller.js";
import LolController from "./controllers/lol_controller.js";

console.debug("starting application");

window.onload = function(){
    const email = document.getElementById('email');
    if (email) {
        email.innerText = 'quentin' + '@' + window.location.hostname;
        email.href = 'mailto:' + email.innerText;
    }

    const phone = document.getElementById('phone');
    if (phone) {
        phone.innerText = '+' + '33' + ' 6' + ' 27' + ' 93' + ' 47' + ' 50' ;
        phone.href = 'tel:' + phone.innerText;
    }
};

window.Stimulus = Application.start();
window.Stimulus.register("tocbot", TocbotController);
window.Stimulus.register("highlightjs", HighlightContoller);
window.Stimulus.register("lol", LolController);


