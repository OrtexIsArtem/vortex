// Copy with a little markup, `code` and [a link](https://…): HTML for the page, plain text for structured data, so one
// sentence serves both.

const escape = (text: string) =>
  text.replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char] ?? char);

const marks = /`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)/g;

/** The copy as HTML: everything escaped, `code` in <code>, links in <a>. */
export function inlineHtml(text: string): string {
  let html = '';
  let last = 0;
  for (const match of text.matchAll(marks)) {
    const [whole, code, label, href] = match;
    html += escape(text.slice(last, match.index));
    html += code !== undefined ? `<code>${escape(code)}</code>` : `<a href="${escape(href ?? '')}">${escape(label ?? '')}</a>`;
    last = match.index + whole.length;
  }
  return html + escape(text.slice(last));
}

/** The copy as plain text: the marks gone, a link's label kept. */
export function inlineText(text: string): string {
  return text.replace(marks, (_whole, code: string | undefined, label: string | undefined) => code ?? label ?? '');
}
