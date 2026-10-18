// @dominiksienkiewicz/api-client — jedno źródło kontraktu fetch dla frontendów.
// Zebrane z 4 rozjeżdżonych implementacji (Azimuth lib/api/client, BookOfStyling lib/api,
// Pragma lib/apiClient, Attestate): env base URL + JSON + 204→null + błąd z body.message.
//
// Zależy wyłącznie od globalnego `fetch` (Node 24 / przeglądarka) — brak zależności runtime.

/** Błąd HTTP niosący status i ciało odpowiedzi (JSON, surowy tekst lub null). */
export class ApiError extends Error {
  /**
   * @param {number} status
   * @param {string} message
   * @param {unknown} [body]
   */
  constructor(status, message, body) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.body = body;
  }
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
      headers: {
        "Content-Type": "application/json",
        ...defaultHeaders,
        ...init.headers,
      },
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
      const message =
        (body && typeof body === "object" && body.message) || res.statusText || `HTTP ${res.status}`;
      throw new ApiError(res.status, message, body);
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
