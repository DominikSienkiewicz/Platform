// Type test of the typed overload, checked by `pnpm typecheck` and never run. pets-schema.d.ts is the
// openapi-typescript output for pets.yaml (platform-openapi-gen), so the test pins the generated `paths` shape.
import { createApiClient, type FilledPath } from "@dominiksienkiewicz/api-client";
import type { components, paths } from "./pets-schema";

type Pet = components["schemas"]["Pet"];
type Equal<A, B> = (<T>() => T extends A ? 1 : 2) extends <T>() => T extends B ? 1 : 2 ? true : false;
const proves = <T extends true>(): T => true as T;

export async function typedConsumerUse(id: string): Promise<void> {
  const client = createApiClient<paths>({ baseUrl: "https://api.example.test" });

  const pets = await client.get("/pets");
  const pet = await client.get(`/pets/${id}`);
  const owned = await client.get(`/owners/${id}/pets/${id}`);
  const created = await client.post("/pets", { name: "Rex" });
  const renamed = await client.patch(`/pets/${id}`);
  const removed = await client.delete(`/pets/${id}`);
  void [
    proves<Equal<typeof pets, Pet[]>>(),
    proves<Equal<typeof pet, Pet>>(),
    proves<Equal<typeof owned, Pet>>(),
    proves<Equal<typeof created, Pet>>(),
    proves<Equal<typeof renamed, Pet>>(),
    proves<Equal<typeof removed, null>>(),
    proves<Equal<FilledPath<"/owners/{ownerId}/pets/{petId}">, `/owners/${string}/pets/${string}`>>(),
  ];

  // @ts-expect-error -- the spec declares no /owners path
  await client.get("/owners");
  // @ts-expect-error -- /pets/{id} has no POST operation
  await client.post(`/pets/${id}`, { name: "Rex" });
  // @ts-expect-error -- POST /pets requires its body
  await client.post("/pets");
  // @ts-expect-error -- the body is NewPet
  await client.post("/pets", { title: "Rex" });
  // @ts-expect-error -- a plain string cannot be checked against the spec
  await client.get(id);

  const untyped: unknown = await client.request("/health");
  void untyped;
}
