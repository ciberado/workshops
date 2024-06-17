
document.addEventListener('slideshowLoaded', function() {
    hljs.registerLanguage('terraform', window.hljsDefineTerraform);
    hljs.highlightAll();
});
