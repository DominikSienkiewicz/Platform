// @dominiksienkiewicz/api-client — jedno źródło kontraktu fetch dla frontendów.
// Zebrane z 4 rozjeżdżonych implementacji (Azimuth lib/api/client, BookOfStyling lib/api,
// Pragma lib/apiClient, Attestate): env base URL + JSON + 204→null + błąd z body.message.
//
// Zależy wyłącznie od globalnego `fetch` (Node 24 / przeglądarka) — brak zależności runtime.

/** Błąd HTTP niosący status i (jeśli był) sparsowane ciało odpowiedzi. */
export class ApiError extends Error {
  constructor(status, message, body) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.body = body;
  }
}

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
    const body = text ? JSON.parse(text) : null;

    if (!res.ok) {
      const message =
        (body && typeof body === "object" && body.message) || res.statusText || `HTTP ${res.status}`;
      throw new ApiError(res.status, message, body);
    }
    return body;
  }

  return {
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
}

/** Domyślny klient (baseUrl z env). */
export const apiClient = createApiClient();
