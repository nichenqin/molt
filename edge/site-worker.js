const CANONICAL_HOST = "remige.app";
const WWW_HOST = "www.remige.app";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname === WWW_HOST) {
      url.hostname = CANONICAL_HOST;
      return Response.redirect(url.toString(), 301);
    }
    return env.ASSETS.fetch(request);
  },
};
