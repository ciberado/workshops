let counter = 1;

/**
 * Transforms a slide, adding a fakémon image if it is a regular slide.
 * 
 * @param {HTMLElement} slideElem 
 */
function fakemonImageProcessor(slideElem) {
    if (slideElem.classList.length !== 0) return;
    slideElem.classList.add('regular');
    const imgElem = document.createElement('img');
    imgElem.classList.add('fakemon');
    imgElem.src = `images/fakemon/${counter++}.png`;
    slideElem.appendChild(imgElem);
}