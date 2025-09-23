// Toggle dark mode persistant via localStorage
Shiny.addCustomMessageHandler("toggle-dark", ({ enable }) => {
  if (enable) {
    document.documentElement.classList.add("dark");
    localStorage.setItem("shiny-dark", "1");
  } else {
    document.documentElement.classList.remove("dark");
    localStorage.removeItem("shiny-dark");
  }
});

// Restaurer au chargement
document.addEventListener("DOMContentLoaded", () => {
  if (localStorage.getItem("shiny-dark") === "1") {
    document.documentElement.classList.add("dark");
    const chk = document.querySelector('#darkmode');
    if (chk) chk.checked = true;
  }
  console.log("Dashboard Financier (vanilla Shiny) prêt.");
});
