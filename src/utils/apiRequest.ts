import { api, Stream } from "misskey-js"
import { APIClient } from "misskey-js/built/api";

class MisskeyAPI {
  public client: APIClient
  constructor(serverUrl: string) {
    this.client = new api.APIClient({ origin: serverUrl})
  }
}

