Shiny.addCustomMessageHandler("toggle-dark", function(message) {
  if (message.enable) {
    document.body.classList.add("dark-mode");
  } else {
    document.body.classList.remove("dark-mode");
  }
});
