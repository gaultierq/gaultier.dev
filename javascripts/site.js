window.onload = function(){
    const button = document.getElementById('email-button');
    if (button) {
        button.onclick = function(){
            window.alert('quentin' + '@' + window.location.hostname);
        };
    }

};