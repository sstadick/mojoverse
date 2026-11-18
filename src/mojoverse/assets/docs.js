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

// Without JavaScript the complete catalog and its ordinary links stay usable.
const filter = document.querySelector("#library-filter");
if (filter) {
  const table = document.querySelector(".md-typeset table");
  table.id = "library-catalog";
  const rows = [...table.querySelectorAll("tbody tr")];
  const count = document.querySelector("#library-count");
  const update = () => {
    const words = filter.value.toLocaleLowerCase().trim().split(/\s+/);
    let visible = 0;
    rows.forEach(row => {
      row.hidden = !words.every(word => row.textContent.toLocaleLowerCase().includes(word));
      if (!row.hidden) visible++;
    });
    count.textContent = visible ? `${visible} of ${rows.length} libraries` : "No matching libraries. Try another name or purpose.";
  };
  filter.closest(".library-filter").hidden = false;
  filter.addEventListener("input", update);
  update();
}
