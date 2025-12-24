// in assets/js/app.js
let Hooks = {}

Hooks.EnterSubmit = {
  mounted() {
    this.el.addEventListener("keydown", (e) => {
      // Check if Enter key is pressed without Shift
      if (e.key === "Enter" && e.shiftKey === false) {
        e.preventDefault(); // Prevent the default new line
        // Dispatch a submit event to the form
        this.el.form.dispatchEvent(new Event("submit",
                                             { bubbles: true, cancelable: true }));
        this.el.value = "";
      }
      // Shift+Enter will naturally create a new line as the default behavior is not prevented
    });
  }
}

export default Hooks

// Don't forget to register your hooks with LiveView
// e.g., let liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}, hooks: Hooks})
