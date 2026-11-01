// Content negotiation for signal pages: /s/{id} with `Accept: text/markdown` returns
// /s/{id}.md (~350 tokens). Requests for /s/{id}.md or .json pass straight through.
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

export async function onRequestGet({ request, env, params, next }) {
  const id = String(params.id || '');
  if (/^[a-z0-9-]+$/.test(id) && prefersMarkdown(request.headers.get('Accept') || '')) {
    const res = await env.ASSETS.fetch(new Request(new URL(`/s/${id}.md`, request.url), { method: 'GET' }));
    if (res.ok) {
      const out = new Response(res.body, res);
      out.headers.set('Content-Type', 'text/markdown; charset=utf-8');
      out.headers.set('Vary', 'Accept');
      out.headers.set('Content-Location', `/s/${id}.md`);
      return out;
    }
  }
  const res = await next();
  if (/\./.test(id)) return res;
  const out = new Response(res.body, res);
  out.headers.append('Vary', 'Accept');
  return out;
}
