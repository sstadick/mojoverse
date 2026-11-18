// Wrapping is the readable default; the toggle only changes presentation.
// Clipboard contents retain their original newlines and indentation.
document.querySelectorAll(".highlight").forEach(block => {
  if (!block.querySelector("pre > code")) return;
  const button = document.createElement("button");
  button.type = "button";
  button.className = "code-wrap";
  button.textContent = "Wrap: on";
  button.setAttribute("aria-label", "Wrap code lines");
  button.setAttribute("aria-pressed", "true");
  button.addEventListener("click", () => {
    const unwrapped = block.classList.toggle("code-unwrapped");
    button.setAttribute("aria-pressed", String(!unwrapped));
    button.textContent = unwrapped ? "Wrap: off" : "Wrap: on";
  });
  block.append(button);
});
