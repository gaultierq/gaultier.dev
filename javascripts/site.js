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