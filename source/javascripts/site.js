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

    tocbot.init({
        // Where to render the table of contents.
        tocSelector: '.js-toc',
        // Where to grab the headings to build the table of contents.
        contentSelector: '.js-toc-content',
        // Which headings to grab inside of the contentSelector element.
        headingSelector: 'h1, h2, h3',
        // For headings inside relative or absolute positioned containers within content.
        hasInnerContainers: false,
        scrollSmooth: false,
    });
};

