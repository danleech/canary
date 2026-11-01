// Content negotiation for the home page: agents that send `Accept: text/markdown` get the
// plain-text brief (/now.md, ~1k tokens) instead of the HTML board. Browsers are unaffected.
const prefersMarkdown = (accept = '') => {
  const q = (type) => {
    const part = accept.split(',').map((s) => s.trim()).find((s) => s.split(';')[0].trim() === type);
    if (!part) return -1;
    const m = part.match(/;\s*q=([0-9.]+)/);
    return m ? parseFloat(m[1]) : 1;
  };
  const md = q('text/markdown');
  return md > 0 && md >= q('text/html');
};

export async function onRequestGet({ request, env, next }) {
  if (prefersMarkdown(request.headers.get('Accept') || '')) {
    const res = await env.ASSETS.fetch(new Request(new URL('/now.md', request.url), { method: 'GET' }));
    const out = new Response(res.body, res);
    out.headers.set('Content-Type', 'text/markdown; charset=utf-8');
    out.headers.set('Vary', 'Accept');
    out.headers.set('Content-Location', '/now.md');
    return out;
  }
  const res = await next();
  const out = new Response(res.body, res);
  out.headers.append('Vary', 'Accept');
  return out;
}
