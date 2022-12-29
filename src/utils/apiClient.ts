import { api, Stream } from "misskey-js";

const origin = "https://misskey.io";
export const noCredential = new api.APIClient({
  origin,
});

let instance: MisskeyClient;

export class MisskeyClient {
  api;
  stream;
  constructor(private token: string, public origin: string) {
    this.api = new api.APIClient({ origin, credential: token });
    this.stream = new Stream(origin, { token });
    console.log(origin, token);
  }
}
