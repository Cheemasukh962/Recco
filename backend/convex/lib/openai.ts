/**
 * Minimal OpenAI Chat Completions client (JSON mode), framework-free.
 *
 * Used by voice:interpretCommand and drafts:createOpener on the "real" path.
 * Both callers wrap this in try/catch and fall back to deterministic local
 * logic, so this module is allowed to throw on any failure.
 */

export type ChatJsonOptions = {
  apiKey: string;
  model: string;
  system: string;
  user: string;
  /** Sampling temperature (default 0.2 for stable, contract-shaped output). */
  temperature?: number;
  timeoutMs?: number;
  fetchImpl?: typeof fetch;
};

/**
 * Call OpenAI with response_format json_object and return the parsed JSON.
 * Throws on HTTP errors, timeouts, or unparseable content.
 */
export async function chatJson(opts: ChatJsonOptions): Promise<unknown> {
  const doFetch = opts.fetchImpl ?? fetch;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? 12000);
  try {
    const res = await doFetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${opts.apiKey}`,
      },
      body: JSON.stringify({
        model: opts.model,
        temperature: opts.temperature ?? 0.2,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: opts.system },
          { role: "user", content: opts.user },
        ],
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`OpenAI HTTP ${res.status}: ${body.slice(0, 200)}`);
    }

    const data = (await res.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const content = data.choices?.[0]?.message?.content;
    if (!content) throw new Error("OpenAI returned no content");
    return JSON.parse(content);
  } finally {
    clearTimeout(timer);
  }
}
