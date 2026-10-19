// @dominiksienkiewicz/api-client — jedno źródło kontraktu fetch dla frontendów.
// Zebrane z 3 rozjechanych implementacji (Azimuth lib/api/client, BookOfStyling lib/api,
// Attestate): env base URL + JSON + 204→null + błąd z body.message.
//
// Zależy wyłącznie od globalnego `fetch` (Node 24 / przeglądarka) — brak zależności runtime.

/**
 * Błąd HTTP niosący status i ciało odpowiedzi (JSON, surowy tekst lub null). Odpowiedź
 * `application/problem+json` (RFC 9457) daje też `problem` z polami ProblemDetail.
 */
export class ApiError extends Error {
  /**
   * @param {number} status
   * @param {string} message
   * @param {unknown} [body]
   * @param {import("./index").ProblemDetail | null} [problem]
   */
  constructor(status, message, body, problem = null) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.body = body;
    this.problem = problem;
  }
}

/**
 * Komunikat błędu: `detail` (RFC 9457), potem `message` (dotychczasowy kształt), `title`, tekst statusu.
 * @param {unknown} body
 * @param {Response} res
 */
function errorMessage(body, res) {
  if (body && typeof body === "object") {
    const fields = /** @type {Record<string, unknown>} */ (body);
    for (const key of ["detail", "message", "title"]) {
      if (typeof fields[key] === "string" && fields[key]) return /** @type {string} */ (fields[key]);
    }
  }
  return res.statusText || `HTTP ${res.status}`;
}

/**
 * @param {string | undefined} explicit
 * @returns {string}
 */
function resolveBaseUrl(explicit) {
  if (explicit != null) return explicit;
  if (typeof process !== "undefined" && process.env?.NEXT_PUBLIC_API_BASE_URL) {
    return process.env.NEXT_PUBLIC_API_BASE_URL;
  }
  return "";
}

// Spread obiektu gubi instancję `Headers` i tablicę par, a nazwy różniące się wielkością liter
// dubluje — `Headers` przyjmuje każdy `HeadersInit` i porównuje nazwy bez względu na wielkość liter.
/**
 * @param {HeadersInit} defaults
 * @param {HeadersInit | undefined} overrides
 * @returns {Headers}
 */
function mergeHeaders(defaults, overrides) {
  const headers = new Headers({ "Content-Type": "application/json" });
  for (const source of [defaults, overrides]) {
    new Headers(source).forEach((value, name) => headers.set(name, value));
  }
  return headers;
}

/**
 * Tworzy klienta HTTP. `baseUrl` domyślnie z NEXT_PUBLIC_API_BASE_URL.
 * @param {{ baseUrl?: string, headers?: Record<string,string> }} [options]
 */
export function createApiClient(options = {}) {
  const baseUrl = resolveBaseUrl(options.baseUrl);
  const defaultHeaders = options.headers ?? {};

  /**
   * @param {string} path
   * @param {RequestInit} [init]
   */
  async function request(path, init = {}) {
    const res = await fetch(`${baseUrl}${path}`, {
      ...init,
      headers: mergeHeaders(defaultHeaders, init.headers),
    });

    if (res.status === 204) return null;

    const text = await res.text();
    let body = null;
    if (text) {
      try {
        body = JSON.parse(text);
      } catch (error) {
        if (res.ok) throw error;
        body = text;
      }
    }

    if (!res.ok) {
      const problemJson = (res.headers.get("Content-Type") ?? "").toLowerCase().includes("application/problem+json");
      const problem =
        problemJson && body && typeof body === "object"
          ? /** @type {import("./index").ProblemDetail} */ ({ status: res.status, ...body })
          : null;
      throw new ApiError(res.status, errorMessage(body, res), body, problem);
    }
    return body;
  }

  // Adnotacja typem z index.d.ts: tsc sprawdza implementację względem publikowanych deklaracji.
  /** @type {import("./index").ApiClient} */
  const client = {
    request,
    get: (path, init) => request(path, { ...init, method: "GET" }),
    post: (path, data, init) =>
      request(path, { ...init, method: "POST", body: data === undefined ? undefined : JSON.stringify(data) }),
    put: (path, data, init) =>
      request(path, { ...init, method: "PUT", body: data === undefined ? undefined : JSON.stringify(data) }),
    patch: (path, data, init) =>
      request(path, { ...init, method: "PATCH", body: data === undefined ? undefined : JSON.stringify(data) }),
    delete: (path, init) => request(path, { ...init, method: "DELETE" }),
  };
  return client;
}

/** Domyślny klient (baseUrl z env). */
export const apiClient = createApiClient();
