interface AssetsBinding {
  fetch(input: Request | string | URL, init?: RequestInit): Promise<Response>;
}

interface Env {
  ASSETS: AssetsBinding;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return env.ASSETS.fetch(request);
  },
};
