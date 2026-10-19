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

// CSRF dla SPA (security starter, platform.security.csrf=spa): Spring Security kładzie token w ciasteczku
// XSRF-TOKEN i oczekuje go z powrotem w nagłówku X-XSRF-TOKEN przy żądaniach zmieniających stan.
const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS", "TRACE"]);

/**
 * @param {import("./index").ApiClientOptions["xsrf"]} option
 * @returns {{ cookie: string, header: string } | null}
 */
function resolveXsrf(option) {
  if (!option) return null;
  const names = option === true ? {} : option;
  return { cookie: names.cookie ?? "XSRF-TOKEN", header: names.header ?? "X-XSRF-TOKEN" };
}

/**
 * Wartość ciasteczka z `document.cookie`; poza przeglądarką (SSR, Node) zawsze null.
 * @param {string} name
 * @returns {string | null}
 */
function readCookie(name) {
  const cookies = /** @type {{ cookie?: unknown } | undefined} */ (globalThis.document)?.cookie;
  if (typeof cookies !== "string") return null;
  for (const pair of cookies.split(";")) {
    const separator = pair.indexOf("=");
    if (separator > 0 && pair.slice(0, separator).trim() === name) {
      return decodeURIComponent(pair.slice(separator + 1).trim());
    }
  }
  return null;
}

/**
 * Tworzy klienta HTTP. `baseUrl` domyślnie z NEXT_PUBLIC_API_BASE_URL.
 * @param {import("./index").ApiClientOptions} [options]
 */
export function createApiClient(options = {}) {
  const baseUrl = resolveBaseUrl(options.baseUrl);
  const defaultHeaders = options.headers ?? {};
  const xsrf = resolveXsrf(options.xsrf);

  /**
   * @param {string} path
   * @param {RequestInit} [init]
   */
  async function request(path, init = {}) {
    const headers = mergeHeaders(defaultHeaders, init.headers);
    if (xsrf && !SAFE_METHODS.has((init.method ?? "GET").toUpperCase()) && !headers.has(xsrf.header)) {
      const token = readCookie(xsrf.cookie);
      if (token) headers.set(xsrf.header, token);
    }
    const res = await fetch(`${baseUrl}${path}`, { ...init, headers });

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
