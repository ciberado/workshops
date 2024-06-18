
document.addEventListener('slideshowLoaded', function() {
    hljs.registerLanguage('terraform', window.hljsDefineTerraform);
    hljs.highlightAll();
});


/**
 * 
 * Transforms a header slide (any slide with `.coverbg` and `h1` or `h2`) by adding
 * a watermark over the image with a gradient. Useful for applying the same aesthetic
 * to every part of the deck.
 * 
 * @param {string} slideElem points to the `section` that implements the current slide. 
 */
function headerSlideProcessor(slideElem) {
  if ((slideElem.classList.contains('coverbg') === true) 
      && (slideElem.querySelector('h1,h2') !== null)) {

    const blockElem = slideElem.querySelector('.block-image');
    if (blockElem === null) return;

    const watermarkElem = document.createElement('div');
    watermarkElem.classList.add('watermark');
    watermarkElem.style = `
          position: absolute;
          width: 100%;
          height: 100%;
          background:          
            linear-gradient(90deg, rgba(0,0,0,0.7) 0%, rgba(0,0,0,0) 30%),
            url("images/innovation-curve.svg");
          background-size: cover, auto;
          background-repeat: no-repeat, no-repeat;
          background-position: center center, center right;      
    `;

    blockElem.prepend(watermarkElem);
  }
}